module RailTests exposing (suite)

import Array
import Expect
import Rail exposing (Conflict, Kind(..), Knob(..), Level, Place(..), Plan, Train)
import Test exposing (Test, describe, test)


{-| Ashby (terminus) - 6 km - Brill (loop) - 6 km - Colley (terminus).
-}
line : List Train -> Level
line trains =
    lineWith 2 trains


lineWith : Int -> List Train -> Level
lineWith brillTracks trains =
    { id = 0
    , title = "Test line"
    , brief = ""
    , clock = 360
    , span = 90
    , stations =
        Array.fromList
            [ { name = "Ashby", km = 0, tracks = 3 }
            , { name = "Brill", km = 6, tracks = brillTracks }
            , { name = "Colley", km = 12, tracks = 3 }
            ]
    , trains = trains
    , par = 0
    }


train : String -> Int -> Int -> Int -> Train
train name from to speed =
    { name = name, ink = 0, from = from, to = to, speed = speed, ready = 0, due = 90, call = 0 }


downLocal : Train
downLocal =
    train "Down local" 0 2 40


upLocal : Train
upLocal =
    train "Up local" 2 0 40


{-| Runs 9 minutes per section at 40 km/h, 12 at 30, 6 at 60.
-}
plan : List ( Int, List Int ) -> Plan
plan =
    List.map (\( d, w ) -> { depart = d, dwells = w })


conflictsOf : Level -> Plan -> List Conflict
conflictsOf level p =
    Rail.conflicts level (Rail.schedule level p)


kinds : List Conflict -> List Kind
kinds =
    List.map .kind


suite : Test
suite =
    describe "Rail"
        [ describe "running times"
            [ test "time over a section rounds up to whole minutes" <|
                \_ ->
                    let
                        level =
                            { line = line [], t = train "t" 0 1 40 }
                    in
                    -- 6 km at 40 km/h is exactly 9 minutes; 5 km would be 7.5, so 8.
                    Expect.equal ( Rail.runTime level.line level.t 0 1, Rail.runTime (fiveKm level.line) level.t 0 1 ) ( 9, 8 )
            , test "arrival adds departures, running times and waits" <|
                \_ ->
                    let
                        level =
                            line [ downLocal ]

                        runs =
                            Rail.schedule level (plan [ ( 4, [ 3 ] ) ])
                    in
                    Expect.equal (List.map .arrival runs) [ 4 + 9 + 3 + 9 ]
            , test "an up train runs from the higher station to the lower one" <|
                \_ ->
                    let
                        level =
                            line [ upLocal ]

                        legs =
                            Rail.schedule level (plan [ ( 0, [ 0 ] ) ]) |> List.concatMap .legs
                    in
                    Expect.equal (List.map (\l -> ( l.segment, l.fromKm, l.toKm )) legs) [ ( 1, 12, 6 ), ( 0, 6, 0 ) ]
            , test "pure run time counts minimum calls" <|
                \_ ->
                    Expect.equal (Rail.pureRunTime (line []) { downLocal | call = 2 }) (9 + 2 + 9)
            ]
        , describe "conflicts on single track"
            [ test "two trains meeting between stations collide head-on" <|
                \_ ->
                    let
                        level =
                            line [ downLocal, { upLocal | ready = 3 } ]

                        found =
                            conflictsOf level (plan [ ( 0, [ 0 ] ), ( 3, [ 0 ] ) ])
                    in
                    case found of
                        [ c ] ->
                            Expect.all
                                [ \x -> Expect.equal x.kind HeadOn
                                , \x -> Expect.equal x.place (Section 1)
                                , \x -> Expect.equal x.trains [ 0, 1 ]

                                -- Down: km 6 at minute 9 to km 12 at 18.
                                -- Up: km 12 at minute 3 to km 6 at 12. They cross at 10.5, km 7.
                                , \x -> Expect.within (Expect.Absolute 1.0e-9) 10.5 x.time
                                , \x -> Expect.within (Expect.Absolute 1.0e-9) 7 x.km
                                ]
                                c

                        _ ->
                            Expect.fail ("expected one conflict, got " ++ Debug.toString found)
            , test "waiting at a passing loop lets them pass safely" <|
                \_ ->
                    let
                        level =
                            line [ downLocal, { upLocal | ready = 3 } ]
                    in
                    conflictsOf level (plan [ ( 0, [ 3 ] ), ( 3, [ 0 ] ) ])
                        |> Expect.equal []
            , test "passing at a loop at the very same minute is allowed" <|
                \_ ->
                    -- Both reach Brill at minute 9 and leave at once.
                    conflictsOf (line [ downLocal, upLocal ]) (plan [ ( 0, [ 0 ] ), ( 0, [ 0 ] ) ])
                        |> Expect.equal []
            , test "one train leaving a section as the other enters it is allowed" <|
                \_ ->
                    -- Up local reaches Ashby at 18; the down local leaves Ashby at 18.
                    conflictsOf (line [ downLocal, upLocal ]) (plan [ ( 18, [ 0 ] ), ( 0, [ 0 ] ) ])
                        |> Expect.equal []
            , test "a fast train catching a slow one on a section is a rear-end conflict" <|
                \_ ->
                    let
                        level =
                            line [ train "Goods" 0 2 30, train "Express" 0 2 60 ]

                        found =
                            conflictsOf level (plan [ ( 0, [ 0 ] ), ( 4, [ 0 ] ) ])
                    in
                    Expect.all
                        [ \f -> Expect.equal (kinds f) [ RearEnd, RearEnd ]
                        , \f -> Expect.equal (List.map .place f) [ Section 0, Section 1 ]
                        ]
                        found
            , test "the express overtakes the goods while it waits in the loop" <|
                \_ ->
                    let
                        level =
                            line [ train "Goods" 0 2 30, train "Express" 0 2 60 ]
                    in
                    -- Goods: Ashby 0, Brill 12, waits there until 24. Express: leaves
                    -- Ashby at 12, runs through Brill at 18, reaches Colley at 24.
                    conflictsOf level (plan [ ( 0, [ 12 ] ), ( 12, [ 0 ] ) ])
                        |> Expect.equal []
            , test "the crossing point of a rear-end conflict is where the lines meet" <|
                \_ ->
                    let
                        level =
                            line [ train "Goods" 0 2 30, train "Express" 0 2 60 ]
                    in
                    -- Goods km = t/2 from 0 to 12; express km = t - 4 from 4 to 10: equal at t = 8, km 4.
                    case conflictsOf level (plan [ ( 0, [ 0 ] ), ( 4, [ 0 ] ) ]) of
                        c :: _ ->
                            Expect.equal ( round (c.time * 1000), round (c.km * 1000) ) ( 8000, 4000 )

                        [] ->
                            Expect.fail "expected a conflict"
            , test "a train that clears a section before another enters is fine" <|
                \_ ->
                    conflictsOf (line [ downLocal, train "Short" 1 2 40 ]) (plan [ ( 0, [ 0 ] ), ( 30, [] ) ])
                        |> Expect.equal []
            ]
        , describe "stations"
            [ test "trains cannot pass at a halt" <|
                \_ ->
                    let
                        level =
                            lineWith 1 [ downLocal, upLocal ]
                    in
                    conflictsOf level (plan [ ( 0, [ 0 ] ), ( 0, [ 0 ] ) ])
                        |> List.map (\c -> ( c.kind, c.place, c.trains ))
                        |> Expect.equal [ ( Crowded, AtStation 1, [ 0, 1 ] ) ]
            , test "a loop holds two trains" <|
                \_ ->
                    let
                        level =
                            line [ downLocal, train "Second down" 0 2 40, upLocal ]
                    in
                    -- The first down train waits at Brill while the up local runs
                    -- through; the second waits at Ashby until the section is clear.
                    conflictsOf level (plan [ ( 0, [ 20 ] ), ( 28, [ 1 ] ), ( 10, [ 0 ] ) ])
                        |> Expect.equal []
            , test "a third train at a two-track loop crowds it" <|
                \_ ->
                    let
                        level =
                            line [ downLocal, train "Second down" 0 2 40, upLocal ]

                        found =
                            -- Both down trains stand at Brill as the up local runs through at 19.
                            conflictsOf level (plan [ ( 0, [ 20 ] ), ( 9, [ 20 ] ), ( 10, [ 0 ] ) ])
                                |> List.filter (\c -> c.kind == Crowded)
                    in
                    Expect.equal (List.map (\c -> ( c.place, c.trains )) found) [ ( AtStation 1, [ 0, 1, 2 ] ) ]
            , test "trains at their own origin or destination do not count" <|
                \_ ->
                    let
                        level =
                            lineWith 1 [ train "Ends at Brill" 0 1 40, train "Starts at Brill" 1 2 40 ]
                    in
                    conflictsOf level (plan [ ( 0, [] ), ( 9, [] ) ])
                        |> Expect.equal []
            ]
        , describe "deadlines and the verdict"
            [ test "arriving exactly on time is not late" <|
                \_ ->
                    let
                        level =
                            line [ { downLocal | due = 21 } ]
                    in
                    Rail.check level (plan [ ( 0, [ 3 ] ) ])
                        |> Expect.all [ .late >> Expect.equal [], .solved >> Expect.equal True ]
            , test "arriving a minute after the deadline is late and unsolved" <|
                \_ ->
                    let
                        level =
                            line [ { downLocal | due = 21 } ]
                    in
                    Rail.check level (plan [ ( 1, [ 3 ] ) ])
                        |> Expect.all [ .late >> Expect.equal [ 0 ], .solved >> Expect.equal False ]
            , test "a conflict means unsolved even if everyone is on time" <|
                \_ ->
                    Rail.check (line [ downLocal, upLocal ]) (plan [ ( 0, [ 0 ] ), ( 3, [ 0 ] ) ])
                        |> .solved
                        |> Expect.equal False
            , test "waiting counts minutes beyond readiness and minimum calls" <|
                \_ ->
                    let
                        level =
                            line [ { downLocal | ready = 2, call = 1 }, upLocal ]
                    in
                    Rail.waiting level (plan [ ( 5, [ 4 ] ), ( 1, [ 0 ] ) ])
                        |> Expect.equal ((5 - 2) + (4 - 1) + 1)
            ]
        , describe "knobs and validation"
            [ test "departures cannot be set before the train is ready" <|
                \_ ->
                    let
                        level =
                            line [ { downLocal | ready = 5 } ]
                    in
                    Rail.setKnob level 0 Departure 1 (plan [ ( 5, [ 0 ] ) ])
                        |> Expect.equal (plan [ ( 5, [ 0 ] ) ])
            , test "waits cannot drop below the minimum call or run off the chart" <|
                \_ ->
                    let
                        level =
                            line [ { downLocal | call = 2 } ]
                    in
                    ( Rail.setKnob level 0 (Dwell 0) 0 (plan [ ( 0, [ 5 ] ) ])
                    , Rail.setKnob level 0 (Dwell 0) 999 (plan [ ( 0, [ 5 ] ) ])
                    )
                        |> Expect.equal ( plan [ ( 0, [ 2 ] ) ], plan [ ( 0, [ 90 ] ) ] )
            , test "knobs sit at the origin and then at each stop along the route" <|
                \_ ->
                    Expect.equal
                        (List.map (Rail.knobStation upLocal) (Rail.knobs upLocal))
                        [ 2, 1 ]
            , test "validate rejects the wrong number of trains" <|
                \_ ->
                    Rail.validate (line [ downLocal, upLocal ]) (plan [ ( 0, [ 0 ] ) ])
                        |> Expect.err
            , test "validate rejects the wrong number of stops" <|
                \_ ->
                    Rail.validate (line [ downLocal ]) (plan [ ( 0, [ 0, 0 ] ) ])
                        |> Expect.err
            , test "validate rejects leaving before ready" <|
                \_ ->
                    Rail.validate (line [ { downLocal | ready = 4 } ]) (plan [ ( 3, [ 0 ] ) ])
                        |> Expect.err
            ]
        , describe "positions"
            [ test "a train is halfway along a section halfway through its run" <|
                \_ ->
                    Rail.schedule (line [ downLocal ]) (plan [ ( 0, [ 4 ] ) ])
                        |> List.head
                        |> Maybe.andThen (\r -> Rail.positionAt r 4.5)
                        |> Expect.equal (Just { km = 3, station = Nothing })
            , test "a waiting train is at its station" <|
                \_ ->
                    Rail.schedule (line [ downLocal ]) (plan [ ( 0, [ 4 ] ) ])
                        |> List.head
                        |> Maybe.andThen (\r -> Rail.positionAt r 11)
                        |> Expect.equal (Just { km = 6, station = Just 1 })
            , test "a train is off the line before it leaves" <|
                \_ ->
                    Rail.schedule (line [ downLocal ]) (plan [ ( 10, [ 0 ] ) ])
                        |> List.head
                        |> Maybe.andThen (\r -> Rail.positionAt r 5)
                        |> Expect.equal Nothing
            ]
        ]


fiveKm : Level -> Level
fiveKm level =
    { level | stations = Array.set 1 { name = "Brill", km = 5, tracks = 2 } level.stations }
