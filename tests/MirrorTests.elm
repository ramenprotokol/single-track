module MirrorTests exposing (suite)

{-| The par search and the par proof run on a JavaScript mirror of the rules
(tools/par-search/rules.mjs). These cases hold that mirror's verdict on
random timetables for every plate; the Elm rules must agree on each one.
-}

import Expect
import Levels
import MirrorCases exposing (cases)
import Rail exposing (Kind(..))
import Test exposing (Test, describe, test)


verdict : Rail.Level -> Rail.Plan -> String
verdict level plan =
    let
        report =
            Rail.check level plan

        letter c =
            case c.kind of
                HeadOn ->
                    "H"

                RearEnd ->
                    "R"

                Crowded ->
                    "C"

        conflicts =
            report.conflicts
                |> List.map (\c -> letter c ++ String.concat (List.map String.fromInt (List.sort c.trains)))
                |> List.sort
    in
    String.join "," conflicts
        ++ "|"
        ++ String.join "," (List.map String.fromInt report.late)
        ++ "|"
        ++ String.fromInt report.waiting


toPlan : List (List Int) -> Rail.Plan
toPlan =
    List.map
        (\t ->
            case t of
                d :: ws ->
                    { depart = d, dwells = ws }

                [] ->
                    { depart = -1, dwells = [] }
        )


suite : Test
suite =
    describe "The JavaScript mirror of the rules"
        [ test "agrees with the Elm rules on every generated timetable" <|
            \_ ->
                cases
                    |> List.filterMap
                        (\( id, times, expected ) ->
                            case Levels.get id of
                                Nothing ->
                                    Just ("no plate " ++ String.fromInt id)

                                Just level ->
                                    let
                                        got =
                                            verdict level (toPlan times)
                                    in
                                    if got == expected then
                                        Nothing

                                    else
                                        Just ("plate " ++ String.fromInt id ++ ": Elm " ++ got ++ ", mirror " ++ expected)
                        )
                    |> List.take 5
                    |> Expect.equal []
        , test "covers every plate, with solved, conflicting and late timetables among them" <|
            \_ ->
                let
                    ids =
                        List.map (\( id, _, _ ) -> id) cases

                    verdicts =
                        List.map (\( _, _, v ) -> v) cases
                in
                Expect.all
                    [ \_ -> Expect.equal (List.all (\l -> List.member l.id ids) Levels.all) True
                    , \_ -> Expect.equal (List.any (String.startsWith "||") verdicts) True
                    , \_ -> Expect.equal (List.any (String.startsWith "|" >> not) verdicts) True
                    , \_ -> Expect.equal (List.any (\v -> String.startsWith "|" v && not (String.startsWith "||" v)) verdicts) True
                    ]
                    ()
        ]
