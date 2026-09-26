module Chart exposing
    ( Config
    , Geometry
    , geometry
    , grabId
    , minutesPerUnit
    , parseGrab
    , view
    )

{-| The Marey diagram: time runs left to right, the line runs top to bottom
with stations spaced by their real distance, and every train is an ink
thread. Steep threads are fast trains, flat stretches are waits.

This module only draws. Pointer events are handled by the page around it,
which reads `data-grab` from whatever the pointer went down on.

-}

import Array
import Clock
import Html exposing (Html)
import Html.Attributes as HA
import Rail exposing (Conflict, Kind(..), Knob(..), Level, Place(..), Report, Run)
import Svg exposing (Svg)
import Svg.Attributes as SA


type alias Geometry =
    { w : Float
    , h : Float
    , left : Float
    , right : Float
    , top : Float
    , bottom : Float
    , span : Int
    , km0 : Float
    , kmLen : Float
    , compact : Bool
    , clock : Int
    }


geometry : Level -> Float -> Geometry
geometry level width =
    let
        compact =
            width < 560

        km0 =
            Array.get 0 level.stations |> Maybe.map (.km >> toFloat) |> Maybe.withDefault 0

        kmLen =
            max 1 (toFloat (Rail.lineLength level))

        perKm =
            if compact then
                11

            else
                14

        plotH =
            clamp
                (if compact then
                    170

                 else
                    230
                )
                400
                (kmLen * perKm)

        -- Room above the plot for the time labels, and below them for knob labels.
        top =
            if compact then
                44

            else
                52

        bottom =
            if compact then
                24

            else
                30
    in
    { w = width
    , h = top + plotH + bottom
    , left =
        if compact then
            80

        else
            126
    , right =
        if compact then
            12

        else
            24
    , top = top
    , bottom = bottom
    , span = level.span
    , km0 = km0
    , kmLen = kmLen
    , compact = compact
    , clock = level.clock
    }


px : Geometry -> Float -> Float
px g t =
    g.left + (t / toFloat g.span) * (g.w - g.left - g.right)


py : Geometry -> Float -> Float
py g km =
    g.top + ((km - g.km0) / g.kmLen) * (g.h - g.top - g.bottom)


{-| How many chart minutes one SVG unit spans horizontally.
-}
minutesPerUnit : Geometry -> Float
minutesPerUnit g =
    toFloat g.span / max 1 (g.w - g.left - g.right)


{-| What a pointer can pick up: a train's departure (its thread or its first
knob) or one of its waits.
-}
grabId : Int -> Knob -> String
grabId train knob =
    case knob of
        Departure ->
            "d" ++ String.fromInt train

        Dwell n ->
            "w" ++ String.fromInt train ++ "." ++ String.fromInt n


parseGrab : String -> Maybe ( Int, Knob )
parseGrab s =
    case String.uncons s of
        Just ( 'd', rest ) ->
            String.toInt rest |> Maybe.map (\t -> ( t, Departure ))

        Just ( 'w', rest ) ->
            case String.split "." rest |> List.map String.toInt of
                [ Just t, Just n ] ->
                    Just ( t, Dwell n )

                _ ->
                    Nothing

        _ ->
            Nothing


type alias Config =
    { level : Level
    , report : Report
    , selected : Int
    , knob : Knob
    , cursor : Maybe Float
    , geometry : Geometry
    , description : String
    }


f1 : Float -> String
f1 v =
    String.fromFloat (toFloat (round (v * 10)) / 10)


view : Config -> Html msg
view config =
    let
        g =
            config.geometry
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ f1 g.w ++ " " ++ f1 g.h)
        , SA.class "marey"
        , HA.attribute "role" "img"
        , HA.attribute "aria-label" config.description
        , SA.preserveAspectRatio "xMidYMin meet"
        ]
        (defs g
            :: grid g
            ++ stations config.level g
            ++ List.concatMap (trainInk config) config.report.runs
            ++ List.map (conflictMark g) config.report.conflicts
            ++ List.map (hitLine g) config.report.runs
            ++ selectedKnobs config
            ++ cursorLine g config.cursor
        )


defs : Geometry -> Svg msg
defs g =
    Svg.defs []
        [ Svg.pattern
            [ SA.id "chart-hatch", SA.width "5", SA.height "5", SA.patternUnits "userSpaceOnUse" ]
            [ Svg.path [ SA.d "M0,0 L5,5 M5,0 L0,5", SA.class "hatch-line" ] [] ]
        , Svg.clipPath [ SA.id "plot-clip" ]
            [ Svg.rect
                [ SA.x (f1 (g.left - 1))
                , SA.y (f1 (g.top - 14))
                , SA.width (f1 (g.w - g.left - g.right + 2))
                , SA.height (f1 (g.h - g.top - g.bottom + 28))
                ]
                []
            ]
        ]



-- GRID


grid : Geometry -> List (Svg msg)
grid g =
    let
        bottomY =
            g.h - g.bottom

        marks =
            List.range 0 g.span
                |> List.filter (\m -> modBy 10 (g.clock + m) == 0)

        labelEvery =
            if g.compact then
                30

            else
                10

        line m =
            let
                ofDay =
                    g.clock + m

                cls =
                    if modBy 60 ofDay == 0 then
                        "grid grid-hour"

                    else if modBy 30 ofDay == 0 then
                        "grid grid-half"

                    else
                        "grid"

                xv =
                    f1 (px g (toFloat m))
            in
            Svg.line [ SA.x1 xv, SA.x2 xv, SA.y1 (f1 (g.top - 20)), SA.y2 (f1 (bottomY + 6)), SA.class cls ] []

        label m =
            let
                ofDay =
                    g.clock + m

                xv =
                    f1 (px g (toFloat m))
            in
            if modBy 60 ofDay == 0 then
                [ Svg.text_ [ SA.x xv, SA.y (f1 (g.top - 26)), SA.class "hour-label", SA.textAnchor "middle" ] [ Svg.text (Clock.hour g.clock m) ]
                , Svg.text_ [ SA.x xv, SA.y (f1 (bottomY + 20)), SA.class "hour-label", SA.textAnchor "middle" ] [ Svg.text (Clock.hour g.clock m) ]
                ]

            else if modBy labelEvery ofDay == 0 then
                [ Svg.text_ [ SA.x xv, SA.y (f1 (g.top - 26)), SA.class "minute-label", SA.textAnchor "middle" ] [ Svg.text (String.fromInt (modBy 60 ofDay)) ] ]

            else
                []

        frame =
            Svg.rect
                [ SA.x (f1 g.left)
                , SA.y (f1 (g.top - 6))
                , SA.width (f1 (g.w - g.left - g.right))
                , SA.height (f1 (g.h - g.top - g.bottom + 12))
                , SA.class "plot-frame"
                ]
                []
    in
    frame :: List.map line marks ++ List.concatMap label marks



-- STATIONS


stations : Level -> Geometry -> List (Svg msg)
stations level g =
    let
        last =
            Array.length level.stations - 1

        x0 =
            f1 (g.left - 4)

        x1 =
            f1 (g.w - g.right + 4)

        rule yv cls =
            Svg.line [ SA.x1 x0, SA.x2 x1, SA.y1 (f1 yv), SA.y2 (f1 yv), SA.class cls ] []

        one ( index, station ) =
            let
                yv =
                    py g (toFloat station.km)

                kind =
                    if index == 0 || index == last then
                        "terminus"

                    else if station.tracks <= 1 then
                        "halt"

                    else if station.tracks == 2 then
                        "loop"

                    else
                        "yard"

                rules =
                    case kind of
                        "loop" ->
                            [ rule (yv - 1.6) "rule rule-loop", rule (yv + 1.6) "rule rule-loop" ]

                        "yard" ->
                            [ rule (yv - 2.4) "rule rule-loop", rule yv "rule rule-loop", rule (yv + 2.4) "rule rule-loop" ]

                        "halt" ->
                            [ rule yv "rule rule-halt" ]

                        _ ->
                            [ rule yv "rule rule-terminus" ]

                note =
                    if g.compact || kind == "terminus" || kind == "loop" then
                        []

                    else
                        [ Svg.text_ [ SA.x (f1 (g.left - 12)), SA.y (f1 (yv + 15)), SA.class "station-note", SA.textAnchor "end" ] [ Svg.text kind ] ]
            in
            rules
                ++ Svg.text_ [ SA.x (f1 (g.left - 12)), SA.y (f1 (yv + 4)), SA.class "station-name", SA.textAnchor "end" ] [ Svg.text station.name ]
                :: note
    in
    List.concatMap one (Array.toIndexedList level.stations)



-- TRAINS


stationKm : Level -> Int -> Float
stationKm level index =
    Array.get index level.stations |> Maybe.map (.km >> toFloat) |> Maybe.withDefault 0


points : Geometry -> Run -> String
points g run =
    run.legs
        |> List.concatMap (\l -> [ ( l.enter, l.fromKm ), ( l.exit, l.toKm ) ])
        |> List.map (\( t, km ) -> f1 (px g (toFloat t)) ++ "," ++ f1 (py g (toFloat km)))
        |> String.join " "


trainOf : Level -> Int -> Maybe Rail.Train
trainOf level index =
    List.drop index level.trains |> List.head


inkClass : Rail.Train -> String
inkClass t =
    "ink-" ++ String.fromInt t.ink


trainInk : Config -> Run -> List (Svg msg)
trainInk config run =
    case trainOf config.level run.train of
        Nothing ->
            []

        Just train ->
            let
                g =
                    config.geometry

                selected =
                    run.train == config.selected

                originY =
                    py g (stationKm config.level train.from)

                destY =
                    py g (stationKm config.level train.to)

                yardWait =
                    if run.departure > train.ready then
                        [ Svg.line
                            [ SA.x1 (f1 (px g (toFloat train.ready)))
                            , SA.x2 (f1 (px g (toFloat run.departure)))
                            , SA.y1 (f1 originY)
                            , SA.y2 (f1 originY)
                            , SA.class ("yard-wait " ++ inkClass train)
                            ]
                            []
                        ]

                    else
                        []

                dueX =
                    px g (toFloat train.due)

                due =
                    [ Svg.path
                        [ SA.d
                            ("M"
                                ++ f1 dueX
                                ++ ","
                                ++ f1 (destY - 8)
                                ++ " V"
                                ++ f1 (destY + 8)
                                ++ " M"
                                ++ f1 (dueX - 4)
                                ++ ","
                                ++ f1 (destY - 8)
                                ++ " H"
                                ++ f1 dueX
                            )
                        , SA.class ("due " ++ inkClass train)
                        ]
                        []
                    ]

                dueLabel =
                    if selected then
                        [ Svg.text_
                            [ SA.x (f1 (dueX + 3))
                            , SA.y
                                (f1
                                    (if train.to > train.from then
                                        destY - 11

                                     else
                                        destY + 18
                                    )
                                )
                            , SA.class "due-label"
                            , SA.textAnchor "middle"
                            ]
                            [ Svg.text ("due " ++ Clock.time config.level.clock train.due) ]
                        ]

                    else
                        []

                late =
                    if run.arrival > train.due then
                        [ Svg.rect
                            [ SA.x (f1 dueX)
                            , SA.y (f1 (destY - 3.5))
                            , SA.width (f1 (max 3 (px g (toFloat (min run.arrival config.level.span)) - dueX)))
                            , SA.height "7"
                            , SA.class "late-band"
                            ]
                            []
                        ]

                    else
                        []

                thread =
                    Svg.polyline
                        [ SA.points (points g run)
                        , SA.class
                            ("thread "
                                ++ inkClass train
                                ++ (if selected then
                                        " selected"

                                    else
                                        ""
                                   )
                            )
                        , SA.clipPath "url(#plot-clip)"
                        ]
                        []

                halo =
                    if selected then
                        [ Svg.polyline [ SA.points (points g run), SA.class "thread-halo", SA.clipPath "url(#plot-clip)" ] [] ]

                    else
                        []
            in
            yardWait ++ due ++ late ++ halo ++ [ thread ] ++ dueLabel


hitLine : Geometry -> Run -> Svg msg
hitLine g run =
    Svg.polyline
        [ SA.points (points g run)
        , SA.class "hit"
        , HA.attribute "data-grab" (grabId run.train Departure)
        , SA.clipPath "url(#plot-clip)"
        ]
        []


selectedKnobs : Config -> List (Svg msg)
selectedKnobs config =
    case ( trainOf config.level config.selected, List.drop config.selected config.report.runs |> List.head ) of
        ( Just train, Just run ) ->
            let
                g =
                    config.geometry

                departure =
                    ( Departure, run.departure, stationKm config.level train.from )

                waits =
                    List.indexedMap (\n c -> ( Dwell n, c.depart, stationKm config.level c.station )) run.calls

                one ( knob, t, km ) =
                    let
                        cx =
                            px g (toFloat t)

                        cy =
                            py g km

                        active =
                            knob == config.knob
                    in
                    Svg.g []
                        [ Svg.circle
                            [ SA.cx (f1 cx)
                            , SA.cy (f1 cy)
                            , SA.r
                                (if active then
                                    "6.5"

                                 else
                                    "5"
                                )
                            , SA.class
                                ("knob "
                                    ++ inkClass train
                                    ++ (if active then
                                            " active"

                                        else
                                            ""
                                       )
                                )
                            ]
                            []
                        , Svg.circle
                            [ SA.cx (f1 cx)
                            , SA.cy (f1 cy)
                            , SA.r "14"
                            , SA.class "hit-knob"
                            , HA.attribute "data-grab" (grabId config.selected knob)
                            ]
                            []
                        ]

                label =
                    List.filter (\( k, _, _ ) -> k == config.knob) (departure :: waits)
                        |> List.head
                        |> Maybe.map (knobLabel config train)
                        |> Maybe.withDefault []
            in
            List.map one (departure :: waits) ++ label

        _ ->
            []


knobLabel : Config -> Rail.Train -> ( Knob, Int, Float ) -> List (Svg msg)
knobLabel config train ( knob, t, km ) =
    let
        g =
            config.geometry

        cx =
            px g (toFloat t)

        cy =
            py g km

        plan =
            List.drop config.selected config.report.runs |> List.head

        text =
            case ( knob, plan ) of
                ( Departure, _ ) ->
                    "leaves " ++ Clock.time config.level.clock t

                ( Dwell n, Just run ) ->
                    let
                        wait =
                            List.drop n run.calls |> List.head |> Maybe.map (\c -> c.depart - c.arrive) |> Maybe.withDefault 0
                    in
                    "waits " ++ Clock.duration wait

                ( Dwell _, Nothing ) ->
                    ""

        nearRight =
            cx > g.w - g.right - 90

        above =
            if train.to > train.from then
                cy - 12

            else
                cy + 22
    in
    [ Svg.text_
        [ SA.x
            (f1
                (if nearRight then
                    cx - 10

                 else
                    cx + 10
                )
            )
        , SA.y (f1 above)
        , SA.class "knob-label"
        , SA.textAnchor
            (if nearRight then
                "end"

             else
                "start"
            )
        ]
        [ Svg.text text ]
    ]



-- CONFLICTS AND THE CURSOR


conflictMark : Geometry -> Conflict -> Svg msg
conflictMark g c =
    case c.place of
        AtStation _ ->
            let
                x0 =
                    px g (toFloat c.from)

                x1 =
                    px g (toFloat c.until)

                w =
                    max 10 (x1 - x0)

                cx =
                    (x0 + x1) / 2
            in
            Svg.rect
                [ SA.x (f1 (cx - w / 2))
                , SA.y (f1 (py g c.km - 6))
                , SA.width (f1 w)
                , SA.height "12"
                , SA.class "conflict"
                ]
                []

        Section _ ->
            Svg.circle
                [ SA.cx (f1 (px g c.time))
                , SA.cy (f1 (py g c.km))
                , SA.r "9"
                , SA.class "conflict"
                ]
                []


cursorLine : Geometry -> Maybe Float -> List (Svg msg)
cursorLine g cursor =
    case cursor of
        Nothing ->
            []

        Just t ->
            let
                xv =
                    px g (clamp 0 (toFloat g.span) t)
            in
            [ Svg.line [ SA.x1 (f1 xv), SA.x2 (f1 xv), SA.y1 (f1 (g.top - 6)), SA.y2 (f1 (g.h - g.bottom + 6)), SA.class "cursor-band" ] []
            , Svg.line [ SA.x1 (f1 xv), SA.x2 (f1 xv), SA.y1 (f1 (g.top - 6)), SA.y2 (f1 (g.h - g.bottom + 6)), SA.class "cursor" ] []
            , Svg.circle [ SA.cx (f1 xv), SA.cy (f1 (g.top - 6)), SA.r "2.5", SA.class "cursor-cap" ] []
            ]
