module Survey exposing (view)

{-| The line as a surveyor would draw it: the railway symbol along its
chainage, loops opening beside the running line, halts as single
platforms, a scale of kilometres, and the trains where they stand at the
chart's cursor.
-}

import Array
import Clock
import Html exposing (Html)
import Html.Attributes as HA
import Rail exposing (Conflict, Level, Place(..), Run)
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


mainY : Float
mainY =
    62


loopY : Float
loopY =
    50


height : Float
height =
    132


view : Config -> Html msg
view config =
    let
        level =
            config.level

        compact =
            config.width < 560

        pad =
            if compact then
                26

            else
                40

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

        tieMarks =
            List.range 0 (floor ((x1 - x0) / 7))
                |> List.map (\i -> "M" ++ f1 (x0 + toFloat i * 7) ++ "," ++ f1 (mainY - 3.5) ++ " v7")
                |> String.join " "

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

        station ( index, s ) =
            let
                x =
                    sx (toFloat s.km)

                lens dy =
                    Svg.path
                        [ SA.d
                            ("M"
                                ++ f1 (x - 24)
                                ++ ","
                                ++ f1 mainY
                                ++ " C"
                                ++ f1 (x - 14)
                                ++ ","
                                ++ f1 (mainY + dy)
                                ++ " "
                                ++ f1 (x + 14)
                                ++ ","
                                ++ f1 (mainY + dy)
                                ++ " "
                                ++ f1 (x + 24)
                                ++ ","
                                ++ f1 mainY
                            )
                        , SA.class "survey-loop"
                        ]
                        []

                platform =
                    Svg.rect [ SA.x (f1 (x - 9)), SA.y (f1 (mainY + 6)), SA.width "18", SA.height "4", SA.class "survey-platform" ] []

                track =
                    if index == 0 || index == last then
                        let
                            dir =
                                if index == 0 then
                                    -1

                                else
                                    1
                        in
                        [ Svg.line [ SA.x1 (f1 (x + dir * 4)), SA.x2 (f1 (x + dir * 4)), SA.y1 (f1 (mainY - 6)), SA.y2 (f1 (mainY + 6)), SA.class "survey-buffer" ] []
                        , Svg.path [ SA.d ("M" ++ f1 (x - dir * 26) ++ "," ++ f1 mainY ++ " Q" ++ f1 (x - dir * 10) ++ "," ++ f1 (mainY - 11) ++ " " ++ f1 (x + dir * 2) ++ "," ++ f1 (mainY - 11)), SA.class "survey-loop" ] []
                        , platform
                        ]

                    else if s.tracks <= 1 then
                        [ platform ]

                    else if s.tracks == 2 then
                        [ lens -24, platform ]

                    else
                        [ lens -24, lens 24 ]

                labelY =
                    if labelRow index == 1 then
                        104

                    else
                        90
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
                slot =
                    slotOf item

                yv =
                    case slot of
                        0 ->
                            mainY

                        1 ->
                            loopY - 4

                        _ ->
                            mainY + 14

                x =
                    sx p.km

                inkIndex =
                    List.drop r.train level.trains |> List.head |> Maybe.map .ink |> Maybe.withDefault 0

                nose =
                    case r.direction of
                        Rail.Down ->
                            "M" ++ f1 (x + 7) ++ "," ++ f1 (yv - 4) ++ " l5,4 l-5,4 z"

                        Rail.Up ->
                            "M" ++ f1 (x - 7) ++ "," ++ f1 (yv - 4) ++ " l-5,4 l5,4 z"
            in
            Svg.g [ SA.class ("survey-train ink-" ++ String.fromInt inkIndex) ]
                [ Svg.rect [ SA.x (f1 (x - 7)), SA.y (f1 (yv - 4)), SA.width "14", SA.height "8", SA.rx "1.5" ] []
                , Svg.path [ SA.d nose ] []
                ]

        live =
            List.filter (\c -> toFloat c.from <= config.cursor && config.cursor <= toFloat c.until) config.conflicts

        conflictMark c =
            Svg.circle [ SA.cx (f1 (sx c.km)), SA.cy (f1 mainY), SA.r "11", SA.class "conflict" ] []

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
                                    , SA.y "116"
                                    , SA.width (f1 unit)
                                    , SA.height "4"
                                    , SA.class
                                        (if modBy 2 i == 0 then
                                            "scale-dark"

                                         else
                                            "scale-light"
                                        )
                                    ]
                                    []
                            )
            in
            blocks
                ++ [ Svg.text_ [ SA.x (f1 x0), SA.y "129", SA.class "survey-caption" ] [ Svg.text "0" ]
                   , Svg.text_ [ SA.x (f1 (x0 + 5 * unit)), SA.y "129", SA.class "survey-caption", SA.textAnchor "middle" ] [ Svg.text "5 km" ]
                   ]

        time =
            Clock.time level.clock (round config.cursor)

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
         , Svg.text_ [ SA.x (f1 x0), SA.y "18", SA.class "survey-title" ] [ Svg.text "Section of the line" ]
         , Svg.text_ [ SA.x (f1 x1), SA.y "18", SA.class "survey-time", SA.textAnchor "end" ] [ Svg.text time ]
         , Svg.line [ SA.x1 (f1 x0), SA.x2 (f1 x1), SA.y1 (f1 mainY), SA.y2 (f1 mainY), SA.class "survey-rail" ] []
         , Svg.path [ SA.d tieMarks, SA.class "survey-ties" ] []
         ]
            ++ List.concatMap station stationsList
            ++ List.map conflictMark live
            ++ List.map trainMark placed
            ++ scale
        )
