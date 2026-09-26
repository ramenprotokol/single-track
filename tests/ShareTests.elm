module ShareTests exposing (suite)

import Expect
import Fuzz exposing (Fuzzer)
import Levels
import Rail exposing (Level, Plan)
import Share
import Test exposing (Test, describe, fuzz, test)


{-| A random plate and a random, in-bounds timetable for it.
-}
levelAndPlan : Fuzzer ( Level, Plan )
levelAndPlan =
    Fuzz.oneOfValues Levels.all
        |> Fuzz.andThen
            (\level ->
                Fuzz.map (Tuple.pair level) (planFor level)
            )


planFor : Level -> Fuzzer Plan
planFor level =
    level.trains
        |> List.map
            (\t ->
                Fuzz.map2 (\d ws -> { depart = d, dwells = ws })
                    (Fuzz.intRange t.ready level.span)
                    (Fuzz.listOfLength (Rail.stopCount t) (Fuzz.intRange t.call level.span))
            )
        |> Fuzz.sequence


roundTrip : Level -> Plan -> Result String Plan
roundTrip level plan =
    Share.parse (Share.encode level.id plan)
        |> Result.andThen
            (\link ->
                if link.plate /= level.id then
                    Err "wrong plate"

                else
                    case link.times of
                        Just times ->
                            Share.toPlan level times

                        Nothing ->
                            Err "no times"
            )


plate : Int -> Level
plate id =
    case Levels.get id of
        Just level ->
            level

        Nothing ->
            Debug.todo ("plate " ++ String.fromInt id ++ " is missing")


suite : Test
suite =
    describe "Share links"
        [ test "a timetable encodes to a short, link-safe fragment" <|
            \_ ->
                Share.encode 1 [ { depart = 0, dwells = [ 3 ] }, { depart = 3, dwells = [ 0 ] } ]
                    |> Expect.equal "p1/0.3-3.0"
        , fuzz levelAndPlan "any valid timetable survives the round trip" <|
            \( level, plan ) ->
                roundTrip level plan |> Expect.equal (Ok plan)
        , fuzz levelAndPlan "encoded links use only unreserved URL characters" <|
            \( level, plan ) ->
                Share.encode level.id plan
                    |> String.all (\c -> Char.isAlphaNum c || c == '.' || c == '-' || c == '/')
                    |> Expect.equal True
        , test "a bare plate link opens the plate fresh" <|
            \_ ->
                Share.parse "p4" |> Expect.equal (Ok { plate = 4, times = Nothing })
        , test "garbage is refused with a message" <|
            \_ ->
                Expect.all
                    (List.map (\s -> \_ -> Expect.err (Share.parse s))
                        [ "", "x", "p", "px", "p-1", "p1/", "p1/a.b", "p1/1..2", "p1/1.2/3", "p1/12345", "p1/-1.0", "p1/1.+2" ]
                    )
                    ()
        , test "overlong fragments are refused before parsing" <|
            \_ ->
                Share.parse ("p1/" ++ String.repeat 400 "1.")
                    |> Expect.err
        , test "a crafted link with too many trains is refused before it is used" <|
            \_ ->
                Share.parse ("p1/" ++ String.join "-" (List.repeat (Share.maxTrains + 1) "0"))
                    |> Expect.err
        , test "a crafted link with too many numbers for one train is refused" <|
            \_ ->
                Share.parse ("p1/" ++ String.join "." (List.repeat (Share.maxValues + 1) "0"))
                    |> Expect.err
        , test "every shipped plate fits within the link limits" <|
            \_ ->
                Levels.all
                    |> List.all
                        (\l ->
                            List.length l.trains
                                <= Share.maxTrains
                                && List.all (\t -> Rail.stopCount t + 1 <= Share.maxValues) l.trains
                                && String.length (Share.encode l.id (List.map (\t -> { depart = l.span, dwells = List.repeat (Rail.stopCount t) l.span }) l.trains))
                                <= Share.maxLength
                        )
                    |> Expect.equal True
        , test "values are at most four digits, so no number can be huge" <|
            \_ ->
                Share.parse "p1/99999.0-3.0" |> Expect.err
        , test "a timetable with the wrong number of trains does not fit" <|
            \_ ->
                Share.toPlan (plate 1) [ [ 0, 3 ] ] |> Expect.err
        , test "a timetable with the wrong number of stops does not fit" <|
            \_ ->
                Share.toPlan (plate 1) [ [ 0, 3, 1 ], [ 3, 0 ] ] |> Expect.err
        , test "a departure before the train is ready does not fit" <|
            \_ ->
                -- On plate 1 the up local is not ready until minute 3.
                Share.toPlan (plate 1) [ [ 0, 3 ], [ 2, 0 ] ] |> Expect.err
        , test "times beyond the chart do not fit" <|
            \_ ->
                Share.toPlan (plate 1) [ [ 0, 3 ], [ 3, 999 ] ] |> Expect.err
        , test "the known solution to plate 1 decodes to what it encodes" <|
            \_ ->
                Share.parse "p1/0.3-3.0"
                    |> Result.andThen (\l -> Share.toPlan (plate l.plate) (Maybe.withDefault [] l.times))
                    |> Result.map (Rail.check (plate 1) >> .solved)
                    |> Expect.equal (Ok True)
        ]
