module HistoryTests exposing (suite)

import Expect
import Fuzz
import Game
import History
import Levels
import Rail exposing (Knob(..))
import Test exposing (Test, describe, fuzz, test)


pushAll : List Int -> History.History Int -> History.History Int
pushAll values h =
    List.foldl History.push h values


repeat : Int -> (a -> a) -> a -> a
repeat n f x =
    if n <= 0 then
        x

    else
        repeat (n - 1) f (f x)


plate1 : Rail.Level
plate1 =
    case Levels.get 1 of
        Just l ->
            l

        Nothing ->
            Debug.todo "plate 1 is missing"


suite : Test
suite =
    describe "Undo and redo"
        [ describe "History"
            [ test "undo returns to the previous state and redo comes back" <|
                \_ ->
                    let
                        h =
                            pushAll [ 1, 2, 3 ] (History.init 0)
                    in
                    Expect.equal
                        ( History.present (History.undo h)
                        , History.present (History.redo (History.undo h))
                        )
                        ( 2, 3 )
            , test "undo with nothing to undo changes nothing" <|
                \_ ->
                    History.init 7 |> History.undo |> History.present |> Expect.equal 7
            , test "a new state after undoing discards the redo branch" <|
                \_ ->
                    let
                        h =
                            pushAll [ 1, 2 ] (History.init 0) |> History.undo |> History.push 9
                    in
                    Expect.equal ( History.canRedo h, History.present (History.redo h) ) ( False, 9 )
            , test "replace changes the present without adding an undo step" <|
                \_ ->
                    let
                        h =
                            History.init 0 |> History.push 1 |> History.replace 5
                    in
                    Expect.equal ( History.present h, History.present (History.undo h), History.depth h ) ( 5, 0, 1 )
            , fuzz (Fuzz.list (Fuzz.intRange 0 99)) "undoing every push returns to the start, redoing every undo returns to the end" <|
                \values ->
                    let
                        n =
                            List.length values

                        h =
                            pushAll values (History.init -1)

                        back =
                            repeat n History.undo h
                    in
                    Expect.equal
                        ( History.present back, History.present (repeat n History.redo back) )
                        ( -1, List.reverse values |> List.head |> Maybe.withDefault -1 )
            , test "only the last 200 states are kept" <|
                \_ ->
                    pushAll (List.range 1 500) (History.init 0)
                        |> History.depth
                        |> Expect.equal 200
            ]
        , describe "Game"
            [ test "each adjustment of a different knob is a move" <|
                \_ ->
                    Game.start plate1
                        |> Game.set 0 (Dwell 0) 3
                        |> Game.set 1 Departure 5
                        |> Game.moves
                        |> Expect.equal 2
            , test "nudging the same knob again continues the same move" <|
                \_ ->
                    let
                        g =
                            Game.start plate1
                                |> Game.nudge 0 (Dwell 0) 1
                                |> Game.nudge 0 (Dwell 0) 1
                                |> Game.nudge 0 (Dwell 0) 1
                    in
                    Expect.equal ( Game.moves g, Game.plan g |> List.map .dwells ) ( 1, [ [ 3 ], [ 0 ] ] )
            , test "undo restores the timetable and the move count; redo reapplies both" <|
                \_ ->
                    let
                        start =
                            Game.start plate1

                        g =
                            start |> Game.set 0 (Dwell 0) 3 |> Game.set 1 Departure 5

                        undone =
                            Game.undo g
                    in
                    Expect.all
                        [ \_ -> Expect.equal (Game.moves undone) 1
                        , \_ -> Expect.equal (Game.plan undone) (Game.plan (Game.set 0 (Dwell 0) 3 start))
                        , \_ -> Expect.equal (Game.plan (Game.redo undone)) (Game.plan g)
                        , \_ -> Expect.equal (Game.plan (Game.undo undone)) (Game.plan start)
                        ]
                        ()
            , test "after an undo, the same knob starts a fresh move rather than rewriting history" <|
                \_ ->
                    let
                        g =
                            Game.start plate1
                                |> Game.set 0 (Dwell 0) 3
                                |> Game.set 0 (Dwell 0) 4
                                |> Game.undo
                                |> Game.set 0 (Dwell 0) 2
                    in
                    Expect.equal ( Game.moves g, Game.plan (Game.undo g) == Rail.initialPlan plate1 ) ( 1, True )
            , test "a change that the bounds turn into no change is not a move" <|
                \_ ->
                    -- The up local is not ready before minute 3.
                    Game.start plate1
                        |> Game.set 1 Departure 0
                        |> Expect.all [ Game.moves >> Expect.equal 0, Game.canUndo >> Expect.equal False ]
            , test "reset returns to the starting timetable and can itself be undone" <|
                \_ ->
                    let
                        g =
                            Game.start plate1 |> Game.set 0 (Dwell 0) 3

                        r =
                            Game.reset g
                    in
                    Expect.equal
                        ( Game.plan r == Rail.initialPlan plate1, Game.moves r, Game.plan (Game.undo r) == Game.plan g )
                        ( True, 0, True )
            , test "solving plate 1 by hand takes one move" <|
                \_ ->
                    let
                        g =
                            Game.start plate1 |> Game.set 0 (Dwell 0) 3
                    in
                    Expect.equal ( (Rail.check plate1 (Game.plan g)).solved, Game.moves g ) ( True, 1 )
            ]
        , describe "Shared timetables"
            [ test "loading a shared timetable over work in progress is one undo step" <|
                \_ ->
                    let
                        mine =
                            Game.start plate1 |> Game.set 0 (Dwell 0) 1

                        loaded =
                            Game.load sharedPlan mine

                        back =
                            Game.undo loaded
                    in
                    Expect.all
                        [ \_ -> Expect.equal ( Game.plan loaded, Game.shared loaded, Game.moves loaded ) ( sharedPlan, True, 0 )
                        , \_ -> Expect.equal ( Game.plan back, Game.shared back, Game.moves back ) ( Game.plan mine, False, 1 )
                        , \_ -> Expect.equal (Game.plan (Game.redo back)) sharedPlan
                        ]
                        ()
            , test "loading the timetable already on screen changes nothing" <|
                \_ ->
                    let
                        g =
                            Game.start plate1 |> Game.load sharedPlan
                    in
                    Expect.equal (Game.load sharedPlan g) g
            , test "a fresh game is not shared" <|
                \_ ->
                    Game.start plate1 |> Game.shared |> Expect.equal False
            , test "the player's first move makes a shared timetable their own" <|
                \_ ->
                    let
                        g =
                            Game.start plate1 |> Game.load sharedPlan |> Game.nudge 1 Departure 1
                    in
                    Expect.equal ( Game.shared g, Game.moves g, Game.shared (Game.undo g) ) ( False, 1, True )
            , test "reset after a shared timetable is the player's own starting point" <|
                \_ ->
                    Game.start plate1
                        |> Game.load sharedPlan
                        |> Game.reset
                        |> Expect.all [ Game.shared >> Expect.equal False, Game.plan >> Expect.equal (Rail.initialPlan plate1) ]
            ]
        ]


{-| Plate 1 solved with the Down local waiting 3 minutes at Brill, as in the
link `#p1/0.3-3.0`.
-}
sharedPlan : Rail.Plan
sharedPlan =
    [ { depart = 0, dwells = [ 3 ] }, { depart = 3, dwells = [ 0 ] } ]
