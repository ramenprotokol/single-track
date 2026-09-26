module Levels exposing (all, count, get, parProven)

{-| The hand-designed plates, from a first meeting to the grand chart.

Every plate has a known solution in tests/LevelTests.elm, and its par is the
least total waiting that the design-time search found for it.

-}

import Array
import Rail exposing (Level, Station)


all : List Level
all =
    [ plate1
    , plate2
    , plate3
    , plate4
    , plate5
    , plate6
    , plate7
    , plate8
    , plate9
    , plate10
    , plate11
    , plate12
    , plate13
    ]


count : Int
count =
    List.length all


get : Int -> Maybe Level
get id =
    List.filter (\l -> l.id == id) all |> List.head


{-| Whether a plate's par is proven to be the least waiting possible:
tools/par-search/prove.mjs tries every timetable with less waiting and none
solves the plate. On the other plates par is the best the search found.
-}
parProven : Int -> Bool
parProven id =
    id <= 8



-- SPEEDS (km/h)


express : Int
express =
    60


local : Int
local =
    40


goods : Int
goods =
    30



-- STATIONS


{-| End of the line. Trains start from and finish in sidings here.
-}
terminus : String -> Int -> Station
terminus name km =
    { name = name, km = km, tracks = 3 }


{-| A passing loop: two tracks, so two trains can meet or overtake.
-}
loop : String -> Int -> Station
loop name km =
    { name = name, km = km, tracks = 2 }


{-| One track: a train may stop, but nothing can pass it here.
-}
halt : String -> Int -> Station
halt name km =
    { name = name, km = km, tracks = 1 }


{-| A station with a yard: three tracks.
-}
yard : String -> Int -> Station
yard name km =
    { name = name, km = km, tracks = 3 }



plate1 : Level
plate1 =
    { id = 1
    , title = "First Meeting"
    , brief = "Two trains, one track. They can pass only at Brill, where the line has a loop. Drag the Down local’s knob at Brill to make it wait there until the Up local arrives."
    , clock = 360
    , span = 40
    , stations =
        Array.fromList
            [ terminus "Ashby" 0
            , loop "Brill" 6
            , terminus "Colley" 12
            ]
    , trains =
        [ { name = "Down local", ink = 0, from = 0, to = 2, speed = local, ready = 0, due = 30, call = 0 }
        , { name = "Up local", ink = 1, from = 2, to = 0, speed = local, ready = 3, due = 30, call = 0 }
        ]
    , par = 3
    }


plate2 : Level
plate2 =
    { id = 2
    , title = "Choose the Loop"
    , brief = "Two loops this time, and the express must not be late. Where should the trains meet?"
    , clock = 390
    , span = 60
    , stations =
        Array.fromList
            [ terminus "Wenlow" 0
            , loop "Ferriby" 8
            , loop "Mardle" 14
            , terminus "Hobb End" 20
            ]
    , trains =
        [ { name = "Down express", ink = 2, from = 0, to = 3, speed = express, ready = 0, due = 24, call = 0 }
        , { name = "Up goods", ink = 3, from = 3, to = 0, speed = goods, ready = 0, due = 44, call = 0 }
        ]
    , par = 2
    }


plate3 : Level
plate3 =
    { id = 3
    , title = "A Halt Is Not a Loop"
    , brief = "Stoke is a halt with a single track: a train may stop there, but two trains cannot pass. Find somewhere else for them to meet."
    , clock = 420
    , span = 50
    , stations =
        Array.fromList
            [ terminus "Pellham" 0
            , halt "Stoke" 6
            , loop "Quarley" 10
            , terminus "Ridgeway" 16
            ]
    , trains =
        [ { name = "Down local", ink = 0, from = 0, to = 3, speed = local, ready = 0, due = 30, call = 0 }
        , { name = "Up local", ink = 1, from = 3, to = 0, speed = local, ready = 0, due = 30, call = 0 }
        ]
    , par = 6
    }


plate4 : Level
plate4 =
    { id = 4
    , title = "Stand Aside"
    , brief = "A fast train behind a slow one. Trains can overtake only at a loop, so the goods must step aside at Upcott and let the express by."
    , clock = 340
    , span = 60
    , stations =
        Array.fromList
            [ terminus "Tamsey" 0
            , loop "Upcott" 8
            , terminus "Vane" 16
            ]
    , trains =
        [ { name = "Down goods", ink = 3, from = 0, to = 2, speed = goods, ready = 0, due = 49, call = 0 }
        , { name = "Down express", ink = 2, from = 0, to = 2, speed = express, ready = 10, due = 36, call = 0 }
        ]
    , par = 22
    }


plate5 : Level
plate5 =
    { id = 5
    , title = "Three’s Company"
    , brief = "Three trains now. The express has the tightest deadline; the goods has time to spare."
    , clock = 480
    , span = 70
    , stations =
        Array.fromList
            [ terminus "Allerby" 0
            , loop "Birkett" 6
            , loop "Carrow" 12
            , terminus "Dunster" 18
            ]
    , trains =
        [ { name = "Down local", ink = 0, from = 0, to = 3, speed = local, ready = 0, due = 40, call = 0 }
        , { name = "Down goods", ink = 3, from = 0, to = 3, speed = goods, ready = 5, due = 60, call = 0 }
        , { name = "Up express", ink = 2, from = 3, to = 0, speed = express, ready = 0, due = 30, call = 0 }
        ]
    , par = 16
    }


plate6 : Level
plate6 =
    { id = 6
    , title = "Two Tracks Only"
    , brief = "A loop has two tracks, so three trains cannot stand at Kestle at once. Stagger them."
    , clock = 620
    , span = 80
    , stations =
        Array.fromList
            [ terminus "Jessop" 0
            , loop "Kestle" 6
            , terminus "Lanyon" 18
            ]
    , trains =
        [ { name = "Down express", ink = 2, from = 0, to = 2, speed = express, ready = 0, due = 45, call = 0 }
        , { name = "Down local", ink = 0, from = 0, to = 2, speed = local, ready = 6, due = 70, call = 0 }
        , { name = "Up goods", ink = 3, from = 2, to = 0, speed = goods, ready = 0, due = 60, call = 0 }
        ]
    , par = 40
    }


plate7 : Level
plate7 =
    { id = 7
    , title = "Calling at All Stations"
    , brief = "The local must stop for at least two minutes at every station, halts included. Keep the express on time behind it."
    , clock = 660
    , span = 80
    , stations =
        Array.fromList
            [ terminus "Marston" 0
            , halt "Nethy" 4
            , loop "Orford" 9
            , halt "Pinner" 13
            , terminus "Quenby" 18
            ]
    , trains =
        [ { name = "Down local", ink = 0, from = 0, to = 4, speed = local, ready = 0, due = 50, call = 2 }
        , { name = "Down express", ink = 2, from = 0, to = 4, speed = express, ready = 10, due = 40, call = 0 }
        , { name = "Up goods", ink = 3, from = 4, to = 0, speed = goods, ready = 0, due = 70, call = 0 }
        ]
    , par = 14
    }


plate8 : Level
plate8 =
    { id = 8
    , title = "Short Workings"
    , brief = "Not every train runs the whole line. The two shuttles work only between Gathorne and Ivymead."
    , clock = 540
    , span = 80
    , stations =
        Array.fromList
            [ terminus "Eldon" 0
            , loop "Fenwick" 5
            , yard "Gathorne" 10
            , loop "Holloway" 16
            , terminus "Ivymead" 22
            ]
    , trains =
        [ { name = "Down express", ink = 2, from = 0, to = 4, speed = express, ready = 10, due = 45, call = 0 }
        , { name = "Up goods", ink = 3, from = 4, to = 0, speed = goods, ready = 0, due = 60, call = 0 }
        , { name = "Down shuttle", ink = 1, from = 2, to = 4, speed = local, ready = 0, due = 30, call = 0 }
        , { name = "Up shuttle", ink = 5, from = 4, to = 2, speed = local, ready = 25, due = 60, call = 0 }
        ]
    , par = 11
    }


plate9 : Level
plate9 =
    { id = 9
    , title = "Morning Rush"
    , brief = "Two expresses, a goods and a local, all before breakfast."
    , clock = 360
    , span = 90
    , stations =
        Array.fromList
            [ terminus "Redmire" 0
            , loop "Saltley" 6
            , loop "Thorne" 12
            , loop "Ulcombe" 18
            , terminus "Vardy" 24
            ]
    , trains =
        [ { name = "Down express", ink = 2, from = 0, to = 4, speed = express, ready = 5, due = 40, call = 0 }
        , { name = "Down goods", ink = 3, from = 0, to = 4, speed = goods, ready = 0, due = 75, call = 0 }
        , { name = "Up local", ink = 0, from = 4, to = 0, speed = local, ready = 0, due = 60, call = 0 }
        , { name = "Up express", ink = 1, from = 4, to = 0, speed = express, ready = 20, due = 60, call = 0 }
        ]
    , par = 25
    }


plate10 : Level
plate10 =
    { id = 10
    , title = "Market Day"
    , brief = "The locals call for a minute everywhere, and Zeal is only a halt."
    , clock = 450
    , span = 100
    , stations =
        Array.fromList
            [ terminus "Wymond" 0
            , loop "Yarrow" 5
            , halt "Zeal" 9
            , loop "Abbots" 14
            , loop "Brampton" 20
            , terminus "Cresswell" 26
            ]
    , trains =
        [ { name = "Down local", ink = 0, from = 0, to = 5, speed = local, ready = 0, due = 70, call = 1 }
        , { name = "Down express", ink = 2, from = 0, to = 5, speed = express, ready = 15, due = 55, call = 0 }
        , { name = "Up goods", ink = 3, from = 5, to = 0, speed = goods, ready = 0, due = 90, call = 0 }
        , { name = "Up local", ink = 1, from = 5, to = 0, speed = local, ready = 20, due = 85, call = 1 }
        ]
    , par = 23
    }


plate11 : Level
plate11 =
    { id = 11
    , title = "The Branch Goods"
    , brief = "Two goods trains finish in the yard at Fold, and a shuttle starts from there. Two expresses need the whole line."
    , clock = 780
    , span = 100
    , stations =
        Array.fromList
            [ terminus "Dallow" 0
            , loop "Easby" 6
            , yard "Fold" 11
            , halt "Garth" 15
            , loop "Hexley" 20
            , terminus "Ingram" 26
            ]
    , trains =
        [ { name = "Down express", ink = 2, from = 0, to = 5, speed = express, ready = 10, due = 50, call = 0 }
        , { name = "Up express", ink = 1, from = 5, to = 0, speed = express, ready = 10, due = 50, call = 0 }
        , { name = "Down goods", ink = 3, from = 0, to = 2, speed = goods, ready = 0, due = 40, call = 0 }
        , { name = "Up goods", ink = 4, from = 5, to = 2, speed = goods, ready = 0, due = 60, call = 0 }
        , { name = "Shuttle", ink = 0, from = 2, to = 5, speed = local, ready = 20, due = 70, call = 0 }
        ]
    , par = 40
    }


plate12 : Level
plate12 =
    { id = 12
    , title = "The Night Mail"
    , brief = "The mail waits for no one, and the up express is close behind it. Everything else must fit around them."
    , clock = 1330
    , span = 120
    , stations =
        Array.fromList
            [ terminus "Kirby" 0
            , loop "Langley" 6
            , loop "Morrow" 12
            , halt "Nabb" 16
            , loop "Oakle" 21
            , terminus "Pendle" 27
            ]
    , trains =
        [ { name = "Down mail", ink = 2, from = 0, to = 5, speed = express, ready = 20, due = 52, call = 0 }
        , { name = "Down goods", ink = 3, from = 0, to = 5, speed = goods, ready = 0, due = 88, call = 0 }
        , { name = "Up local", ink = 0, from = 5, to = 0, speed = local, ready = 0, due = 54, call = 1 }
        , { name = "Up goods", ink = 4, from = 5, to = 0, speed = goods, ready = 15, due = 118, call = 0 }
        , { name = "Up express", ink = 1, from = 5, to = 0, speed = express, ready = 40, due = 70, call = 0 }
        ]
    , par = 88
    }


plate13 : Level
plate13 =
    { id = 13
    , title = "The Grand Chart"
    , brief = "The whole Ashby line at once: six trains, seven stations. Take your time."
    , clock = 300
    , span = 130
    , stations =
        Array.fromList
            [ terminus "Ashby" 0
            , loop "Brill" 5
            , loop "Colley" 11
            , halt "Dunmore" 15
            , loop "Eskdale" 20
            , loop "Farthing" 26
            , terminus "Gorsedene" 32
            ]
    , trains =
        [ { name = "Down express", ink = 2, from = 0, to = 6, speed = express, ready = 10, due = 57, call = 0 }
        , { name = "Down local", ink = 0, from = 0, to = 6, speed = local, ready = 0, due = 92, call = 1 }
        , { name = "Down goods", ink = 3, from = 0, to = 6, speed = goods, ready = 20, due = 112, call = 0 }
        , { name = "Up express", ink = 1, from = 6, to = 0, speed = express, ready = 30, due = 74, call = 0 }
        , { name = "Up local", ink = 5, from = 6, to = 0, speed = local, ready = 0, due = 62, call = 1 }
        , { name = "Up goods", ink = 4, from = 6, to = 0, speed = goods, ready = 5, due = 122, call = 0 }
        ]
    , par = 119
    }
