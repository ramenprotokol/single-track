module Clock exposing (duration, hour, roman, time)

{-| Formatting for the chart: railway times, durations and plate numerals.
-}


{-| A chart minute as a 24-hour railway time, wrapping at midnight.
-}
time : Int -> Int -> String
time clockStart minute =
    let
        m =
            modBy (24 * 60) (clockStart + minute)
    in
    pad (m // 60) ++ ":" ++ pad (modBy 60 m)


{-| The hour at a chart minute, as the old charts labelled it: "6h".
-}
hour : Int -> Int -> String
hour clockStart minute =
    String.fromInt (modBy 24 ((clockStart + minute) // 60)) ++ "h"


duration : Int -> String
duration minutes =
    String.fromInt minutes ++ " min"


pad : Int -> String
pad n =
    String.padLeft 2 '0' (String.fromInt n)


roman : Int -> String
roman n =
    let
        table =
            [ ( 1000, "M" ), ( 900, "CM" ), ( 500, "D" ), ( 400, "CD" ), ( 100, "C" ), ( 90, "XC" ), ( 50, "L" ), ( 40, "XL" ), ( 10, "X" ), ( 9, "IX" ), ( 5, "V" ), ( 4, "IV" ), ( 1, "I" ) ]

        go left pairs acc =
            case pairs of
                [] ->
                    acc

                ( value, numeral ) :: rest ->
                    if left >= value then
                        go (left - value) pairs (acc ++ numeral)

                    else
                        go left rest acc
    in
    if n <= 0 then
        String.fromInt n

    else
        go n table ""
