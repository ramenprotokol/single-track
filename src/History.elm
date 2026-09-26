module History exposing
    ( History
    , canRedo
    , canUndo
    , depth
    , init
    , present
    , push
    , redo
    , replace
    , undo
    )

{-| Undo and redo over immutable states. Because every state is an immutable
value, a history is just two stacks either side of the present one.
-}


type History a
    = History
        { past : List a
        , present : a
        , future : List a
        }


{-| How many earlier states we keep. Older ones are forgotten.
-}
limit : Int
limit =
    200


init : a -> History a
init value =
    History { past = [], present = value, future = [] }


present : History a -> a
present (History h) =
    h.present


{-| Record a new state. Anything that had been undone is gone for good.
-}
push : a -> History a -> History a
push value (History h) =
    History
        { past = List.take limit (h.present :: h.past)
        , present = value
        , future = []
        }


{-| Change the present state without adding an undo step (for example while
the same knob is nudged repeatedly). Redo is no longer possible.
-}
replace : a -> History a -> History a
replace value (History h) =
    History { h | present = value, future = [] }


undo : History a -> History a
undo (History h) =
    case h.past of
        previous :: older ->
            History { past = older, present = previous, future = h.present :: h.future }

        [] ->
            History h


redo : History a -> History a
redo (History h) =
    case h.future of
        next :: later ->
            History { past = h.present :: h.past, present = next, future = later }

        [] ->
            History h


canUndo : History a -> Bool
canUndo (History h) =
    not (List.isEmpty h.past)


canRedo : History a -> Bool
canRedo (History h) =
    not (List.isEmpty h.future)


{-| Number of states that can be undone.
-}
depth : History a -> Int
depth (History h) =
    List.length h.past
