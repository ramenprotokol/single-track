module Rail exposing
    ( Call
    , Conflict
    , Direction(..)
    , Kind(..)
    , Knob(..)
    , Leg
    , Level
    , Place(..)
    , Plan
    , Report
    , Run
    , Station
    , Train
    , TrainPlan
    , check
    , conflicts
    , direction
    , initialPlan
    , knobBounds
    , knobStation
    , knobValue
    , knobs
    , legKm
    , lineLength
    , positionAt
    , pureRunTime
    , route
    , runTime
    , schedule
    , setKnob
    , stopCount
    , validate
    , waiting
    )

{-| The pure heart of the game: a single-track line, the trains on it, the
player's timetable (a Plan), the running times that follow from it, and the
rules that decide whether two trains collide.

Times are whole minutes counted from the start of the level's chart. A train
occupies a section of single track from the moment it leaves one station
until the moment it reaches the next. Two trains may never be on the same
section at once, so they can only meet or overtake at a station. A station
holds as many trains at once as it has tracks: a halt has one, a passing
loop two.

The two kinds of place count minutes differently, on purpose. A section is
free again the minute its train arrives at the next station (zero headway).
A train standing at a station holds its track from its arrival minute to its
departure minute, both included, so at a one-track halt a train cannot
arrive in the minute another leaves: the swap takes at least a minute.

-}

import Array exposing (Array)



-- LINE AND TRAINS


type alias Station =
    { name : String
    , km : Int
    , tracks : Int
    }


type alias Train =
    { name : String
    , ink : Int
    , from : Int
    , to : Int
    , speed : Int
    , ready : Int
    , due : Int
    , call : Int
    }


type alias Level =
    { id : Int
    , title : String
    , brief : String
    , clock : Int
    , span : Int
    , stations : Array Station
    , trains : List Train
    , par : Int
    }


type Direction
    = Down
    | Up


direction : Train -> Direction
direction train =
    if train.to > train.from then
        Down

    else
        Up


{-| Station indices the train visits, in running order.
-}
route : Train -> List Int
route train =
    if train.to >= train.from then
        List.range train.from train.to

    else
        List.reverse (List.range train.to train.from)


{-| Intermediate stations where the train may wait.
-}
stopCount : Train -> Int
stopCount train =
    max 0 (abs (train.to - train.from) - 1)


stationKm : Level -> Int -> Int
stationKm level index =
    Array.get index level.stations
        |> Maybe.map .km
        |> Maybe.withDefault 0


lineLength : Level -> Int
lineLength level =
    stationKm level (Array.length level.stations - 1) - stationKm level 0


{-| Minutes a train needs for the section between two adjacent stations,
rounded up to the next whole minute.
-}
runTime : Level -> Train -> Int -> Int -> Int
runTime level train a b =
    let
        km =
            abs (stationKm level b - stationKm level a)
    in
    if train.speed <= 0 then
        0

    else
        (km * 60 + train.speed - 1) // train.speed


{-| Running time from origin to destination with the minimum calls and no
extra waiting.
-}
pureRunTime : Level -> Train -> Int
pureRunTime level train =
    let
        stations =
            route train

        runs =
            List.map2 (runTime level train) stations (List.drop 1 stations)
    in
    List.sum runs + train.call * stopCount train



-- THE PLAYER'S TIMETABLE


type alias TrainPlan =
    { depart : Int
    , dwells : List Int
    }


type alias Plan =
    List TrainPlan


initialPlan : Level -> Plan
initialPlan level =
    List.map
        (\t -> { depart = t.ready, dwells = List.repeat (stopCount t) t.call })
        level.trains


{-| Something the player can adjust: when a train leaves its origin, or how
long it waits at its n-th intermediate stop.
-}
type Knob
    = Departure
    | Dwell Int


knobs : Train -> List Knob
knobs train =
    Departure :: List.map Dwell (List.range 0 (stopCount train - 1))


{-| The station a knob sits at.
-}
knobStation : Train -> Knob -> Int
knobStation train knob =
    let
        step =
            case direction train of
                Down ->
                    1

                Up ->
                    -1
    in
    case knob of
        Departure ->
            train.from

        Dwell n ->
            train.from + step * (n + 1)


{-| Inclusive bounds for a knob: no train leaves before it is ready, and a
train waits at least its minimum call.
-}
knobBounds : Level -> Train -> Knob -> ( Int, Int )
knobBounds level train knob =
    case knob of
        Departure ->
            ( train.ready, level.span )

        Dwell _ ->
            ( train.call, level.span )


knobValue : Knob -> TrainPlan -> Int
knobValue knob tp =
    case knob of
        Departure ->
            tp.depart

        Dwell n ->
            List.drop n tp.dwells |> List.head |> Maybe.withDefault 0


{-| Set a knob, clamped to its bounds. Unknown trains or knobs leave the plan
unchanged.
-}
setKnob : Level -> Int -> Knob -> Int -> Plan -> Plan
setKnob level trainIndex knob value plan =
    case List.drop trainIndex level.trains |> List.head of
        Nothing ->
            plan

        Just train ->
            let
                ( lo, hi ) =
                    knobBounds level train knob

                v =
                    clamp lo hi value
            in
            List.indexedMap
                (\i tp ->
                    if i /= trainIndex then
                        tp

                    else
                        case knob of
                            Departure ->
                                { tp | depart = v }

                            Dwell n ->
                                { tp
                                    | dwells =
                                        List.indexedMap
                                            (\j d ->
                                                if j == n then
                                                    v

                                                else
                                                    d
                                            )
                                            tp.dwells
                                }
                )
                plan


{-| Check a plan's shape and bounds against a level. Used for plans that
arrive from outside (a shared link).
-}
validate : Level -> Plan -> Result String Plan
validate level plan =
    let
        checkOne train tp =
            if List.length tp.dwells /= stopCount train then
                Err ("the " ++ train.name ++ " has the wrong number of stops")

            else if tp.depart < train.ready || tp.depart > level.span then
                Err ("the " ++ train.name ++ " leaves at a time outside the chart")

            else if List.any (\d -> d < train.call || d > level.span) tp.dwells then
                Err ("the " ++ train.name ++ " has a wait outside the allowed range")

            else
                Ok ()

        results =
            List.map2 checkOne level.trains plan
    in
    if List.length plan /= List.length level.trains then
        Err "it has the wrong number of trains"

    else
        case List.filterMap errorOf results of
            first :: _ ->
                Err first

            [] ->
                Ok plan


errorOf : Result String () -> Maybe String
errorOf r =
    case r of
        Err e ->
            Just e

        Ok _ ->
            Nothing



-- RUNNING TIMES


{-| A train on one section of single track, from `enter` (leaving one
station) to `exit` (arriving at the next).
-}
type alias Leg =
    { train : Int
    , segment : Int
    , enter : Int
    , exit : Int
    , fromKm : Int
    , toKm : Int
    }


{-| A train standing at an intermediate station, both ends inclusive.
-}
type alias Call =
    { train : Int
    , station : Int
    , arrive : Int
    , depart : Int
    }


type alias Run =
    { train : Int
    , direction : Direction
    , departure : Int
    , arrival : Int
    , legs : List Leg
    , calls : List Call
    }


schedule : Level -> Plan -> List Run
schedule level plan =
    List.indexedMap Tuple.pair (List.map2 Tuple.pair level.trains plan)
        |> List.map (\( i, ( t, tp ) ) -> runOf level i t tp)


runOf : Level -> Int -> Train -> TrainPlan -> Run
runOf level index train tp =
    let
        stations =
            route train

        pairs =
            List.map2 Tuple.pair stations (List.drop 1 stations)

        -- Waits apply at each intermediate stop; none after the last section.
        waits =
            tp.dwells ++ [ 0 ]

        step ( ( a, b ), wait ) ( clock, legsSoFar, callsSoFar ) =
            let
                arrive =
                    clock + runTime level train a b

                leg =
                    { train = index
                    , segment = min a b
                    , enter = clock
                    , exit = arrive
                    , fromKm = stationKm level a
                    , toKm = stationKm level b
                    }

                newCalls =
                    if b == train.to then
                        callsSoFar

                    else
                        { train = index, station = b, arrive = arrive, depart = arrive + wait } :: callsSoFar
            in
            ( arrive + wait, leg :: legsSoFar, newCalls )

        ( _, revLegs, revCalls ) =
            List.foldl step ( tp.depart, [], [] ) (List.map2 Tuple.pair pairs waits)

        legs =
            List.reverse revLegs
    in
    { train = index
    , direction = direction train
    , departure = tp.depart
    , arrival =
        List.reverse legs
            |> List.head
            |> Maybe.map .exit
            |> Maybe.withDefault tp.depart
    , legs = legs
    , calls = List.reverse revCalls
    }



-- CONFLICTS


type Kind
    = HeadOn
    | RearEnd
    | Crowded


type Place
    = Section Int
    | AtStation Int


{-| A collision. `time` and `km` locate the mark on the chart; `from` and
`until` give the minutes during which the rule is broken.
-}
type alias Conflict =
    { kind : Kind
    , trains : List Int
    , place : Place
    , time : Float
    , km : Float
    , from : Int
    , until : Int
    }


conflicts : Level -> List Run -> List Conflict
conflicts level runs =
    sectionConflicts runs ++ stationConflicts level runs


sectionConflicts : List Run -> List Conflict
sectionConflicts runs =
    let
        indexed =
            List.indexedMap Tuple.pair runs

        pairsOf =
            indexed
                |> List.concatMap
                    (\( i, a ) ->
                        List.filterMap
                            (\( j, b ) ->
                                if j > i then
                                    Just ( a, b )

                                else
                                    Nothing
                            )
                            indexed
                    )
    in
    List.concatMap
        (\( a, b ) ->
            List.concatMap
                (\la ->
                    List.filterMap (legConflict a b la) b.legs
                )
                a.legs
        )
        pairsOf


legConflict : Run -> Run -> Leg -> Leg -> Maybe Conflict
legConflict a b la lb =
    if la.segment == lb.segment && la.enter < lb.exit && lb.enter < la.exit then
        let
            from =
                max la.enter lb.enter

            until =
                min la.exit lb.exit

            ( time, km ) =
                meetingPoint la lb (toFloat from) (toFloat until)
        in
        Just
            { kind =
                if a.direction == b.direction then
                    RearEnd

                else
                    HeadOn
            , trains = [ la.train, lb.train ]
            , place = Section la.segment
            , time = time
            , km = km
            , from = from
            , until = until
            }

    else
        Nothing


{-| Where a train is on its section at time t (clamped to the section).
-}
legKm : Leg -> Float -> Float
legKm leg t =
    let
        d =
            toFloat (leg.exit - leg.enter)

        f =
            if d <= 0 then
                1

            else
                clamp 0 1 ((t - toFloat leg.enter) / d)
    in
    toFloat leg.fromKm + f * toFloat (leg.toKm - leg.fromKm)


{-| Where to mark two trains on one section: the crossing of their lines if
they cross during the overlap. Otherwise one train simply followed the other
into an occupied section (a rear-end that never catches up), and the mark
goes on the follower's own thread, at the moment and place it entered.
-}
meetingPoint : Leg -> Leg -> Float -> Float -> ( Float, Float )
meetingPoint la lb t0 t1 =
    let
        gap t =
            legKm la t - legKm lb t

        g0 =
            gap t0

        g1 =
            gap t1

        follower =
            if la.enter >= lb.enter then
                la

            else
                lb
    in
    if g0 == 0 then
        ( t0, legKm la t0 )

    else if g0 * g1 < 0 || g1 == 0 then
        let
            t =
                t0 + (g0 / (g0 - g1)) * (t1 - t0)
        in
        ( t, legKm la t )

    else
        ( t0, legKm follower t0 )


stationConflicts : Level -> List Run -> List Conflict
stationConflicts level runs =
    let
        calls =
            List.concatMap .calls runs
    in
    Array.toIndexedList level.stations
        |> List.concatMap
            (\( index, station ) ->
                let
                    here =
                        List.filter (\c -> c.station == index) calls
                in
                crowding station.tracks here
                    |> List.map
                        (\group ->
                            let
                                from =
                                    List.map .arrive group |> List.maximum |> Maybe.withDefault 0

                                until =
                                    List.map .depart group |> List.minimum |> Maybe.withDefault from
                            in
                            { kind = Crowded
                            , trains = List.map .train group |> List.sort
                            , place = AtStation index
                            , time = toFloat (from + until) / 2
                            , km = toFloat station.km
                            , from = from
                            , until = until
                            }
                        )
            )


{-| Groups of calls that share a moment when there are more trains than
tracks. The most crowded moments always begin at some train's arrival, so
those are the only instants we need to look at.
-}
crowding : Int -> List Call -> List (List Call)
crowding tracks calls =
    calls
        |> List.map (\p -> List.filter (\q -> q.arrive <= p.arrive && p.arrive <= q.depart) calls)
        |> List.filter (\group -> List.length group > tracks)
        |> List.foldl
            (\group acc ->
                let
                    key =
                        List.map .train group |> List.sort
                in
                if List.any (\g -> (List.map .train g |> List.sort) == key) acc then
                    acc

                else
                    acc ++ [ group ]
            )
            []



-- VERDICT


type alias Report =
    { runs : List Run
    , conflicts : List Conflict
    , late : List Int
    , waiting : Int
    , solved : Bool
    }


{-| Extra minutes spent waiting beyond each train's earliest start and
minimum calls. Lower is more elegant.
-}
waiting : Level -> Plan -> Int
waiting level plan =
    List.map2
        (\t tp -> (tp.depart - t.ready) + List.sum (List.map (\d -> d - t.call) tp.dwells))
        level.trains
        plan
        |> List.sum


check : Level -> Plan -> Report
check level plan =
    let
        runs =
            schedule level plan

        found =
            conflicts level runs

        late =
            List.map2 Tuple.pair level.trains runs
                |> List.filter (\( t, r ) -> r.arrival > t.due)
                |> List.map (Tuple.second >> .train)

        valid =
            case validate level plan of
                Ok _ ->
                    True

                Err _ ->
                    False
    in
    { runs = runs
    , conflicts = found
    , late = late
    , waiting = waiting level plan
    , solved = valid && List.isEmpty found && List.isEmpty late
    }



-- WHERE IS EVERYONE


{-| A train's place on the line at time t: its kilometre and, when it is
standing at a station, which one. Nothing before it leaves or after it
arrives.
-}
positionAt : Run -> Float -> Maybe { km : Float, station : Maybe Int }
positionAt run t =
    if t < toFloat run.departure || t > toFloat run.arrival then
        Nothing

    else
        case List.filter (\c -> toFloat c.arrive <= t && t <= toFloat c.depart) run.calls of
            c :: _ ->
                run.legs
                    |> List.filter (\l -> l.exit == c.arrive)
                    |> List.head
                    |> Maybe.map (\l -> { km = toFloat l.toKm, station = Just c.station })

            [] ->
                run.legs
                    |> List.filter (\l -> toFloat l.enter <= t && t <= toFloat l.exit)
                    |> List.head
                    |> Maybe.map (\l -> { km = legKm l t, station = Nothing })
