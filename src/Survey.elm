module Survey exposing (view)

{-| The line as a surveyor would engrave it: a railway of two fine rails and
sleepers along its chainage, loops opening beside the running line, halts
as single platforms, a scale of kilometres, and the trains, as numbered ink
blocks in their thread colours, where they stand at the chart's cursor.
-}

import Array
import Clock
import Html exposing (Html)
import Html.Attributes as HA
import Rail exposing (Conflict, Level, Run)
import Svg exposing (Svg)
import Svg.Attributes as SA


type alias Config =
    { level : Level
    , runs : List Run
    , conflicts : List Conflict
    , cursor : Float
    , width : Float
    }


f1 : Float -> String
f1 v =
    String.fromFloat (toFloat (round (v * 10)) / 10)


{-| The running line.
-}
mainY : Float
mainY =
    76


{-| How far a loop or a yard road bows away from the running line.
-}
bow : Float
bow =
    26


{-| Where a train standing on a loop road sits (three quarters of the bow,
the peak of the curve).
-}
roadOffset : Float
roadOffset =
    bow * 0.75


height : Float
height =
    170


view : Config -> Html msg
view config =
    let
        level =
            config.level

        compact =
            config.width < 560

        pad =
            if compact then
                28

            else
                44

        km0 =
            Array.get 0 level.stations |> Maybe.map (.km >> toFloat) |> Maybe.withDefault 0

        kmLen =
            max 1 (toFloat (Rail.lineLength level))

        sx km =
            pad + ((km - km0) / kmLen) * (config.width - 2 * pad)

        x0 =
            sx km0

        x1 =
            sx (km0 + kmLen)

        last =
            Array.length level.stations - 1

        -- Two fine rails and a sleeper every five units.
        rails =
            [ Svg.line [ SA.x1 (f1 (x0 - 6)), SA.x2 (f1 (x1 + 6)), SA.y1 (f1 (mainY - 1.6)), SA.y2 (f1 (mainY - 1.6)), SA.class "survey-rail" ] []
            , Svg.line [ SA.x1 (f1 (x0 - 6)), SA.x2 (f1 (x1 + 6)), SA.y1 (f1 (mainY + 1.6)), SA.y2 (f1 (mainY + 1.6)), SA.class "survey-rail" ] []
            , Svg.path
                [ SA.d
                    (List.range 0 (floor ((x1 - x0 + 12) / 5))
                        |> List.map (\i -> "M" ++ f1 (x0 - 6 + toFloat i * 5) ++ "," ++ f1 (mainY - 3.4) ++ " v6.8")
                        |> String.join " "
                    )
                , SA.class "survey-ties"
                ]
                []
            ]

        stationsList =
            Array.toIndexedList level.stations

        -- Alternate label rows where stations sit close together.
        labelRow index =
            let
                gapBefore =
                    case ( Array.get (index - 1) level.stations, Array.get index level.stations ) of
                        ( Just a, Just b ) ->
                            sx (toFloat b.km) - sx (toFloat a.km)

                        _ ->
                            999
            in
            if gapBefore < 78 && modBy 2 index == 1 then
                1

            else
                0

        -- A loop road: a pair of rails bowing away from the running line.
        road x dy =
            let
                curve half depth =
                    Svg.path
                        [ SA.d
                            ("M"
                                ++ f1 (x - half)
                                ++ ","
                                ++ f1 mainY
                                ++ " C"
                                ++ f1 (x - half * 0.55)
                                ++ ","
                                ++ f1 (mainY + depth)
                                ++ " "
                                ++ f1 (x + half * 0.55)
                                ++ ","
                                ++ f1 (mainY + depth)
                                ++ " "
                                ++ f1 (x + half)
                                ++ ","
                                ++ f1 mainY
                            )
                        , SA.class "survey-loop"
                        ]
                        []

                sign =
                    if dy < 0 then
                        -1

                    else
                        1
            in
            [ curve 26 (dy - sign * 2.4), curve 23 (dy + sign * 1.6) ]

        station ( index, s ) =
            let
                x =
                    sx (toFloat s.km)

                platform =
                    Svg.rect [ SA.x (f1 (x - 11)), SA.y (f1 (mainY + 6)), SA.width "22", SA.height "4", SA.class "survey-platform" ] []

                track =
                    if index == 0 || index == last then
                        let
                            dir =
                                if index == 0 then
                                    -1

                                else
                                    1

                            siding lift =
                                Svg.path
                                    [ SA.d
                                        ("M"
                                            ++ f1 (x - dir * 28)
                                            ++ ","
                                            ++ f1 mainY
                                            ++ " Q"
                                            ++ f1 (x - dir * 10)
                                            ++ ","
                                            ++ f1 (mainY - lift)
                                            ++ " "
                                            ++ f1 (x + dir * 4)
                                            ++ ","
                                            ++ f1 (mainY - lift)
                                        )
                                    , SA.class "survey-loop"
                                    ]
                                    []
                        in
                        [ siding 11
                        , siding 14
                        , Svg.line [ SA.x1 (f1 (x + dir * 6)), SA.x2 (f1 (x + dir * 6)), SA.y1 (f1 (mainY - 5)), SA.y2 (f1 (mainY + 5)), SA.class "survey-buffer" ] []
                        , Svg.line [ SA.x1 (f1 (x + dir * 6)), SA.x2 (f1 (x + dir * 6)), SA.y1 (f1 (mainY - 17)), SA.y2 (f1 (mainY - 10)), SA.class "survey-buffer" ] []
                        , platform
                        ]

                    else if s.tracks <= 1 then
                        [ platform ]

                    else if s.tracks == 2 then
                        road x -bow ++ [ platform ]

                    else
                        road x -bow ++ road x bow

                labelY =
                    if labelRow index == 1 then
                        mainY + 56

                    else
                        mainY + 42
            in
            track
                ++ [ Svg.text_ [ SA.x (f1 x), SA.y (f1 labelY), SA.class "survey-name", SA.textAnchor "middle" ] [ Svg.text s.name ] ]

        -- Where each train is, and which road it is standing on at a station.
        placed =
            config.runs
                |> List.filterMap (\r -> Rail.positionAt r config.cursor |> Maybe.map (\p -> ( r, p )))

        slotOf ( r, p ) =
            case p.station of
                Nothing ->
                    0

                Just st ->
                    placed
                        |> List.filter (\( r2, p2 ) -> p2.station == Just st && r2.train < r.train)
                        |> List.length

        trainMark (( r, p ) as item) =
            let
                yv =
                    case slotOf item of
                        0 ->
                            mainY

                        1 ->
                            mainY - roadOffset

                        _ ->
                            mainY + roadOffset

                x =
                    sx p.km

                inkIndex =
                    List.drop r.train level.trains |> List.head |> Maybe.map .ink |> Maybe.withDefault 0

                nose =
                    case r.direction of
                        Rail.Down ->
                            "M" ++ f1 (x + 13) ++ "," ++ f1 (yv - 6.5) ++ " l6.5,6.5 l-6.5,6.5 z"

                        Rail.Up ->
                            "M" ++ f1 (x - 13) ++ "," ++ f1 (yv - 6.5) ++ " l-6.5,6.5 l6.5,6.5 z"
            in
            Svg.g [ SA.class ("survey-train ink-" ++ String.fromInt inkIndex) ]
                [ Svg.path [ SA.d nose, SA.class "survey-train-body" ] []
                , Svg.rect [ SA.x (f1 (x - 13)), SA.y (f1 (yv - 6.5)), SA.width "26", SA.height "13", SA.rx "1", SA.class "survey-train-body" ] []
                , Svg.text_ [ SA.x (f1 x), SA.y (f1 (yv + 4)), SA.class "survey-train-no", SA.textAnchor "middle" ] [ Svg.text (String.fromInt (r.train + 1)) ]
                ]

        live =
            List.filter (\c -> toFloat c.from <= config.cursor && config.cursor <= toFloat c.until) config.conflicts

        conflictMark c =
            Svg.circle [ SA.cx (f1 (sx c.km)), SA.cy (f1 mainY), SA.r "13", SA.class "conflict" ] []

        scaleY =
            height - 26

        scale =
            let
                unit =
                    sx (km0 + 1) - sx km0

                blocks =
                    List.range 0 4
                        |> List.map
                            (\i ->
                                Svg.rect
                                    [ SA.x (f1 (x0 + toFloat i * unit))
                                    , SA.y (f1 scaleY)
                                    , SA.width (f1 unit)
                                    , SA.height "3.5"
                                    , SA.class
                                        (if modBy 2 i == 0 then
                                            "scale-dark"

                                         else
                                            "scale-light"
                                        )
                                    ]
                                    []
                            )

                tick i =
                    Svg.line
                        [ SA.x1 (f1 (x0 + toFloat i * unit))
                        , SA.x2 (f1 (x0 + toFloat i * unit))
                        , SA.y1 (f1 (scaleY - 3))
                        , SA.y2 (f1 scaleY)
                        , SA.class "scale-tick"
                        ]
                        []
            in
            blocks
                ++ List.map tick [ 0, 5 ]
                ++ [ Svg.text_ [ SA.x (f1 x0), SA.y (f1 (scaleY + 15)), SA.class "survey-caption", SA.textAnchor "middle" ] [ Svg.text "0" ]
                   , Svg.text_ [ SA.x (f1 (x0 + 5 * unit)), SA.y (f1 (scaleY + 15)), SA.class "survey-caption", SA.textAnchor "middle" ] [ Svg.text "5 km" ]
                   ]

        time =
            Clock.time level.clock (round config.cursor)

        -- A neat line round the drawing, as on an engraved plate.
        neat =
            Svg.rect [ SA.x "0.5", SA.y "0.5", SA.width (f1 (config.width - 1)), SA.height (f1 (height - 1)), SA.class "survey-neat" ] []

        summary =
            "Survey drawing of the line at "
                ++ time
                ++ ". "
                ++ (if List.isEmpty placed then
                        "No trains are on the line."

                    else
                        String.fromInt (List.length placed) ++ " on the line."
                   )
    in
    Svg.svg
        [ SA.viewBox ("0 0 " ++ f1 config.width ++ " " ++ f1 height)
        , SA.class "survey"
        , HA.attribute "role" "img"
        , HA.attribute "aria-label" summary
        ]
        ([ Svg.defs []
            [ Svg.pattern
                [ SA.id "survey-hatch", SA.width "5", SA.height "5", SA.patternUnits "userSpaceOnUse" ]
                [ Svg.path [ SA.d "M0,0 L5,5 M5,0 L0,5", SA.class "hatch-line" ] [] ]
            ]
         , neat
         , Svg.text_ [ SA.x (f1 x0), SA.y "24", SA.class "survey-title" ] [ Svg.text "Section of the line" ]
         , Svg.text_ [ SA.x (f1 x1), SA.y "26", SA.class "survey-time", SA.textAnchor "end" ] [ Svg.text time ]
         ]
            ++ rails
            ++ List.concatMap station stationsList
            ++ List.map conflictMark live
            ++ List.map trainMark placed
            ++ scale
        )
