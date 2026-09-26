module Share exposing
    ( Link
    , encode
    , maxLength
    , maxTrains
    , maxValues
    , parse
    , toPlan
    )

{-| Timetables as link fragments, so a solution can be shared.

    p3                  plate 3, fresh chart
    p3/0.3-3.0          plate 3, first train leaves at minute 0 and waits
                        3 minutes at its one stop, the second leaves at
                        minute 3 and waits 0

Only digits, letters, dots, dashes and one slash appear, so the link
survives being pasted into chat apps and emails.

-}

import Rail exposing (Level, Plan)


type alias Link =
    { plate : Int
    , times : Maybe (List (List Int))
    }


{-| Longer fragments are refused before any parsing, so a crafted link can
never make the page do much work.
-}
maxLength : Int
maxLength =
    400


{-| No plate has more trains than this, or more numbers per train (one
departure and a wait at each stop).
-}
maxTrains : Int
maxTrains =
    8


maxValues : Int
maxValues =
    8


encode : Int -> Plan -> String
encode plate plan =
    "p"
        ++ String.fromInt plate
        ++ "/"
        ++ String.join "-"
            (List.map
                (\tp -> String.join "." (List.map String.fromInt (tp.depart :: tp.dwells)))
                plan
            )


parse : String -> Result String Link
parse fragment =
    if String.length fragment > maxLength then
        Err "That link is too long to be a timetable."

    else
        case String.split "/" fragment of
            [ plate ] ->
                parsePlate plate |> Result.map (\p -> { plate = p, times = Nothing })

            [ plate, times ] ->
                Result.map2 (\p t -> { plate = p, times = Just t })
                    (parsePlate plate)
                    (parseTimes times)

            _ ->
                Err "That link is not a timetable from this game."


parsePlate : String -> Result String Int
parsePlate s =
    if String.startsWith "p" s then
        number (String.dropLeft 1 s)
            |> Result.fromMaybe "That link does not name a plate."

    else
        Err "That link is not a timetable from this game."


parseTimes : String -> Result String (List (List Int))
parseTimes s =
    let
        pieces =
            String.split "-" s
    in
    if List.length pieces > maxTrains then
        Err "That link's timetable has more trains than any plate."

    else
        let
            trains =
                List.map (String.split ".") pieces
        in
        if List.any (\t -> List.length t > maxValues) trains then
            Err "That link's timetable has more stops than any plate."

        else
            let
                numbers =
                    List.map (List.map number) trains
            in
            if List.any (List.any ((==) Nothing)) numbers then
                Err "That link's timetable has something other than whole minutes in it."

            else
                Ok (List.map (List.filterMap identity) numbers)


{-| Whole minutes, at most four digits, no signs.
-}
number : String -> Maybe Int
number s =
    if String.isEmpty s || String.length s > 4 || not (String.all Char.isDigit s) then
        Nothing

    else
        String.toInt s


{-| Fit parsed times to a level, checking every train and bound.
-}
toPlan : Level -> List (List Int) -> Result String Plan
toPlan level times =
    let
        plan =
            List.filterMap
                (\t ->
                    case t of
                        depart :: dwells ->
                            Just { depart = depart, dwells = dwells }

                        [] ->
                            Nothing
                )
                times
    in
    if List.length plan /= List.length times then
        Err "That link's timetable is missing a train."

    else
        Rail.validate level plan
            |> Result.mapError (\e -> "That link's timetable does not fit this plate: " ++ e ++ ".")
