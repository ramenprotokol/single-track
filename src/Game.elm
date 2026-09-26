module Game exposing
    ( Game
    , Snapshot
    , canRedo
    , canUndo
    , fromLink
    , level
    , moves
    , nudge
    , plan
    , preview
    , reset
    , set
    , start
    , startWith
    , undo
    , redo
    )

{-| A level being played: the timetable, its undo history and the move
count. Everything here is pure, so the whole game can be tested without a
browser.

A move is one adjustment of one knob (a train's departure or one of its
waits). Nudging the same knob again straight away continues the same move,
so dragging or arrow-keying a departure by twelve minutes is one move and
one undo step.

-}

import History exposing (History)
import Rail exposing (Knob, Level, Plan)


type alias Snapshot =
    { plan : Plan
    , moves : Int
    }


type Game
    = Game
        { level : Level
        , history : History Snapshot
        , lastKnob : Maybe ( Int, Knob )
        , fromLink : Bool
        }


start : Level -> Game
start lvl =
    Game
        { level = lvl
        , history = History.init { plan = Rail.initialPlan lvl, moves = 0 }
        , lastKnob = Nothing
        , fromLink = False
        }


{-| Open a level with a timetable that came from a shared link.
-}
startWith : Level -> Plan -> Game
startWith lvl p =
    Game
        { level = lvl
        , history = History.init { plan = p, moves = 0 }
        , lastKnob = Nothing
        , fromLink = True
        }


level : Game -> Level
level (Game g) =
    g.level


plan : Game -> Plan
plan (Game g) =
    (History.present g.history).plan


moves : Game -> Int
moves (Game g) =
    (History.present g.history).moves


fromLink : Game -> Bool
fromLink (Game g) =
    g.fromLink


canUndo : Game -> Bool
canUndo (Game g) =
    History.canUndo g.history


canRedo : Game -> Bool
canRedo (Game g) =
    History.canRedo g.history


{-| The plan with one knob set, without committing it. Used while dragging.
-}
preview : Int -> Knob -> Int -> Game -> Plan
preview train knob value (Game g) =
    Rail.setKnob g.level train knob value (History.present g.history).plan


{-| Set a knob (clamped to its bounds) and record it.
-}
set : Int -> Knob -> Int -> Game -> Game
set train knob value (Game g) =
    let
        current =
            History.present g.history

        next =
            Rail.setKnob g.level train knob value current.plan
    in
    if next == current.plan then
        Game g

    else if g.lastKnob == Just ( train, knob ) then
        Game
            { g
                | history = History.replace { current | plan = next } g.history
            }

    else
        Game
            { g
                | history = History.push { plan = next, moves = current.moves + 1 } g.history
                , lastKnob = Just ( train, knob )
            }


nudge : Int -> Knob -> Int -> Game -> Game
nudge train knob delta ((Game g) as game) =
    let
        current =
            List.drop train (plan game) |> List.head
    in
    case current of
        Nothing ->
            game

        Just tp ->
            set train knob (Rail.knobValue knob tp + delta) (Game g)


undo : Game -> Game
undo (Game g) =
    Game { g | history = History.undo g.history, lastKnob = Nothing }


redo : Game -> Game
redo (Game g) =
    Game { g | history = History.redo g.history, lastKnob = Nothing }


{-| Back to the starting timetable. Reset is itself undoable.
-}
reset : Game -> Game
reset (Game g) =
    let
        fresh =
            { plan = Rail.initialPlan g.level, moves = 0 }
    in
    if History.present g.history == fresh then
        Game g

    else
        Game { g | history = History.push fresh g.history, lastKnob = Nothing }
