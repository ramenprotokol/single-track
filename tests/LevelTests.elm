module LevelTests exposing (suite)

import Array
import Expect
import KnownSolutions exposing (solutions)
import Levels
import Rail exposing (Level, Plan)
import Test exposing (Test, describe, test)


toPlan : List (List Int) -> Plan
toPlan =
    List.map
        (\t ->
            case t of
                d :: ws ->
                    { depart = d, dwells = ws }

                [] ->
                    { depart = -1, dwells = [] }
        )


solutionFor : Level -> Maybe Plan
solutionFor level =
    solutions
        |> List.filter (\( id, _ ) -> id == level.id)
        |> List.head
        |> Maybe.map (Tuple.second >> toPlan)


suite : Test
suite =
    describe "Levels"
        [ test "at least twelve plates ship, numbered from 1 with no gaps" <|
            \_ ->
                let
                    ids =
                        List.map .id Levels.all
                in
                Expect.all
                    [ \_ -> Expect.atLeast 12 (List.length ids)
                    , \_ -> Expect.equal ids (List.range 1 (List.length ids))
                    ]
                    ()
        , test "every plate has a known solution" <|
            \_ ->
                Expect.equal (List.map Tuple.first solutions) (List.map .id Levels.all)
        , test "the difficulty grows: never fewer trains than the plate before" <|
            \_ ->
                let
                    counts =
                        List.map (.trains >> List.length) Levels.all
                in
                Expect.equal counts (List.sortBy identity counts)
        , describe "each plate" (List.map plateTests Levels.all)
        ]


plateTests : Level -> Test
plateTests level =
    let
        name =
            "Plate " ++ String.fromInt level.id ++ " (" ++ level.title ++ ")"
    in
    describe name
        [ test "its known solution is valid, conflict-free and on time" <|
            \_ ->
                case solutionFor level of
                    Nothing ->
                        Expect.fail "no known solution"

                    Just plan ->
                        let
                            report =
                                Rail.check level plan
                        in
                        Expect.all
                            [ \_ -> Expect.ok (Rail.validate level plan)
                            , \_ -> Expect.equal [] (List.map .kind report.conflicts)
                            , \_ -> Expect.equal [] report.late
                            , \_ -> Expect.equal True report.solved
                            ]
                            ()
        , test "its par is the waiting of the known solution" <|
            \_ ->
                solutionFor level
                    |> Maybe.map (Rail.waiting level)
                    |> Expect.equal (Just level.par)
        , test "the starting timetable is not already a solution" <|
            \_ ->
                Rail.check level (Rail.initialPlan level)
                    |> .solved
                    |> Expect.equal False
        , test "the starting timetable has at least one conflict to fix" <|
            \_ ->
                Rail.check level (Rail.initialPlan level)
                    |> .conflicts
                    |> List.isEmpty
                    |> Expect.equal False
        , test "stations run downhill in distance, with termini at both ends" <|
            \_ ->
                let
                    stations =
                        Array.toList level.stations

                    kms =
                        List.map .km stations

                    ends =
                        [ List.head stations, List.head (List.reverse stations) ]
                            |> List.filterMap identity
                            |> List.map .tracks
                in
                Expect.all
                    [ \_ -> Expect.equal kms (List.sort kms)
                    , \_ -> Expect.equal (List.length kms) (List.length (unique kms))
                    , \_ -> Expect.equal ends [ 3, 3 ]
                    , \_ -> Expect.atLeast 3 (List.length stations)
                    , \_ -> Expect.equal True (List.all (\s -> s.tracks >= 1 && s.tracks <= 3) stations)
                    ]
                    ()
        , test "trains are well formed and fit the chart" <|
            \_ ->
                let
                    n =
                        Array.length level.stations

                    ok t =
                        t.from
                            /= t.to
                            && t.from
                            >= 0
                            && t.from
                            < n
                            && t.to
                            >= 0
                            && t.to
                            < n
                            && t.speed
                            > 0
                            && t.ready
                            >= 0
                            && t.due
                            <= level.span
                            && t.ready
                            + Rail.pureRunTime level t
                            <= t.due
                in
                Expect.equal [] (List.filter (not << ok) level.trains |> List.map .name)
        , test "each train has its own ink and name" <|
            \_ ->
                let
                    inks =
                        List.map .ink level.trains

                    names =
                        List.map .name level.trains
                in
                Expect.all
                    [ \_ -> Expect.equal (List.length inks) (List.length (unique inks))
                    , \_ -> Expect.equal (List.length names) (List.length (unique names))
                    , \_ -> Expect.equal True (List.all (\i -> i >= 0 && i < 6) inks)
                    ]
                    ()
        ]


unique : List comparable -> List comparable
unique =
    List.foldl
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []
