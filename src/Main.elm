port module Main exposing (main)

{-| The page: plates, the chart editor, the run, undo and share links.
All game rules live in Rail, Game and Share; this module wires them to the
browser.
-}

import Array
import Browser
import Browser.Events
import Browser.Navigation as Nav
import Chart
import Clock
import Dict exposing (Dict)
import Game exposing (Game)
import Html exposing (Html, a, aside, button, dd, div, dl, dt, figure, figcaption, footer, h1, h2, h3, header, input, kbd, label, li, main_, nav, ol, p, section, span, strong, text, ul)
import Html.Attributes as HA
import Html.Events as HE
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Levels
import Rail exposing (Conflict, Kind(..), Knob(..), Level, Place(..), Plan, Report)
import Share
import Survey
import Time
import Url exposing (Url)



-- PORTS


port save : String -> Cmd msg


port setTheme : String -> Cmd msg


port copyLink : String -> Cmd msg


port copied : (Bool -> msg) -> Sub msg


port motion : (Bool -> msg) -> Sub msg



-- MODEL


type Playback
    = Idle
    | Playing
    | Done


type Theme
    = Auto
    | Light
    | Dark


type alias Record =
    { waiting : Int
    , moves : Int
    }


type alias Drag =
    { train : Int
    , knob : Knob
    , startX : Float
    , scale : Float
    , startValue : Int
    , value : Int
    }


type alias Model =
    { key : Nav.Key
    , games : Dict Int Game
    , plate : Int
    , selected : Int
    , knob : Knob
    , drag : Maybe Drag
    , playback : Playback
    , cursor : Float
    , notice : Maybe String
    , width : Int
    , reducedMotion : Bool
    , prefersDark : Bool
    , theme : Theme
    , records : Dict Int Record
    , share : Maybe String
    , copyState : Maybe Bool
    , verdict : Maybe Verdict
    , home : String
    }


{-| What the last completed run showed.
-}
type alias Verdict =
    { solved : Bool
    , waiting : Int
    , moves : Int
    , fromLink : Bool
    }


type alias Flags =
    { width : Int
    , reducedMotion : Bool
    , prefersDark : Bool
    , saved : String
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.map4 Flags
        (Decode.oneOf [ Decode.field "width" Decode.int, Decode.succeed 1024 ])
        (Decode.oneOf [ Decode.field "reducedMotion" Decode.bool, Decode.succeed False ])
        (Decode.oneOf [ Decode.field "prefersDark" Decode.bool, Decode.succeed False ])
        (Decode.oneOf [ Decode.field "saved" Decode.string, Decode.succeed "" ])


type alias Saved =
    { records : Dict Int Record
    , theme : Theme
    }


{-| Saved progress is read leniently: anything unreadable is ignored.
-}
savedDecoder : Decoder Saved
savedDecoder =
    Decode.map2 Saved
        (Decode.oneOf
            [ Decode.field "records"
                (Decode.keyValuePairs
                    (Decode.map2 Record (Decode.field "waiting" Decode.int) (Decode.field "moves" Decode.int))
                    |> Decode.map
                        (List.filterMap (\( k, v ) -> String.toInt k |> Maybe.map (\i -> ( i, v ))) >> Dict.fromList)
                )
            , Decode.succeed Dict.empty
            ]
        )
        (Decode.oneOf
            [ Decode.field "theme" Decode.string
                |> Decode.map
                    (\s ->
                        case s of
                            "light" ->
                                Light

                            "dark" ->
                                Dark

                            _ ->
                                Auto
                    )
            , Decode.succeed Auto
            ]
        )


encodeSaved : Model -> String
encodeSaved model =
    Encode.encode 0
        (Encode.object
            [ ( "v", Encode.int 1 )
            , ( "records"
              , Encode.object
                    (Dict.toList model.records
                        |> List.map
                            (\( k, r ) ->
                                ( String.fromInt k, Encode.object [ ( "waiting", Encode.int r.waiting ), ( "moves", Encode.int r.moves ) ] )
                            )
                    )
              )
            , ( "theme", Encode.string (themeName model.theme) )
            ]
        )


themeName : Theme -> String
themeName theme =
    case theme of
        Light ->
            "light"

        Dark ->
            "dark"

        Auto ->
            ""


init : Decode.Value -> Url -> Nav.Key -> ( Model, Cmd Msg )
init rawFlags url key =
    let
        flags =
            Decode.decodeValue flagsDecoder rawFlags
                |> Result.withDefault { width = 1024, reducedMotion = False, prefersDark = False, saved = "" }

        saved =
            Decode.decodeString savedDecoder flags.saved
                |> Result.withDefault { records = Dict.empty, theme = Auto }

        firstUnsolved =
            Levels.all
                |> List.filter (\l -> not (Dict.member l.id saved.records))
                |> List.head
                |> Maybe.map .id
                |> Maybe.withDefault 1

        model =
            { key = key
            , games = Dict.empty
            , plate = firstUnsolved
            , selected = 0
            , knob = Departure
            , drag = Nothing
            , playback = Idle
            , cursor = 0
            , notice = Nothing
            , width = flags.width
            , reducedMotion = flags.reducedMotion
            , prefersDark = flags.prefersDark
            , theme = saved.theme
            , records = saved.records
            , share = Nothing
            , copyState = Nothing
            , verdict = Nothing
            , home = url.path
            }
                |> openPlate firstUnsolved
    in
    ( route url model, setTheme (themeName saved.theme) )



-- HELPERS


level : Model -> Level
level model =
    Levels.get model.plate
        |> Maybe.withDefault (Maybe.withDefault fallbackLevel (List.head Levels.all))


fallbackLevel : Level
fallbackLevel =
    { id = 0, title = "", brief = "", clock = 0, span = 60, stations = Array.empty, trains = [], par = 0 }


game : Model -> Game
game model =
    Dict.get model.plate model.games
        |> Maybe.withDefault (Game.start (level model))


{-| The timetable on screen: the committed one, or the one being dragged.
-}
livePlan : Model -> Plan
livePlan model =
    case model.drag of
        Just d ->
            Game.preview d.train d.knob d.value (game model)

        Nothing ->
            Game.plan (game model)


openPlate : Int -> Model -> Model
openPlate id model =
    case Levels.get id of
        Nothing ->
            model

        Just lvl ->
            { model
                | plate = id
                , games =
                    if Dict.member id model.games then
                        model.games

                    else
                        Dict.insert id (Game.start lvl) model.games
                , selected = 0
                , knob = Departure
                , drag = Nothing
                , playback = Idle
                , cursor = 0
                , share = Nothing
                , copyState = Nothing
                , verdict = Nothing
            }


route : Url -> Model -> Model
route url model =
    case url.fragment of
        Nothing ->
            model

        Just "" ->
            model

        Just fragment ->
            case Share.parse fragment of
                Err message ->
                    { model | notice = Just (message ++ " Showing plate " ++ String.fromInt model.plate ++ " instead.") }

                Ok link ->
                    case Levels.get link.plate of
                        Nothing ->
                            { model | notice = Just ("There is no plate " ++ String.fromInt link.plate ++ ". Showing plate " ++ String.fromInt model.plate ++ " instead.") }

                        Just lvl ->
                            let
                                switched =
                                    if link.plate == model.plate then
                                        model

                                    else
                                        openPlate link.plate { model | notice = Nothing }
                            in
                            case link.times of
                                Nothing ->
                                    switched

                                Just times ->
                                    case Share.toPlan lvl times of
                                        Err message ->
                                            { switched | notice = Just (message ++ " Showing the plate as it was.") }

                                        Ok plan ->
                                            if plan == Game.plan (game switched) then
                                                switched

                                            else
                                                { switched
                                                    | games = Dict.insert lvl.id (Game.startWith lvl plan) switched.games
                                                    , notice = Just ("Opened a shared timetable for plate " ++ Clock.roman lvl.id ++ ". Press Run to see it work, or change it.")
                                                    , playback = Idle
                                                    , cursor = 0
                                                    , verdict = Nothing
                                                }


updateGame : (Game -> Game) -> Model -> Model
updateGame f model =
    { model
        | games = Dict.insert model.plate (f (game model)) model.games
        , playback =
            if model.playback == Playing then
                Idle

            else
                model.playback
        , share = Nothing
        , copyState = Nothing
        , verdict = Nothing
    }


trainCount : Model -> Int
trainCount model =
    List.length (level model).trains


selectedTrain : Model -> Maybe Rail.Train
selectedTrain model =
    List.drop model.selected (level model).trains |> List.head


{-| When the run should stop: once the last train is in, or at the chart's edge.
-}
endTime : Level -> Report -> Float
endTime lvl report =
    report.runs
        |> List.map .arrival
        |> List.maximum
        |> Maybe.withDefault lvl.span
        |> (\t -> min lvl.span (t + 1))
        |> toFloat


chartWidth : Int -> Float
chartWidth viewport =
    if viewport >= 1180 then
        toFloat (clamp 700 900 (viewport - 440))

    else
        toFloat (clamp 320 900 (viewport - 40))



-- UPDATE


type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | Select Int
    | SelectKnob Int Knob
    | Nudge Int Knob Int
    | PointerDown { train : Int, knob : Knob, clientX : Float, width : Float }
    | PointerMove Float
    | PointerUp
    | PointerCancel
    | ChartKey String Bool
    | Undo
    | Redo
    | Reset
    | TogglePlay
    | Frame Float
    | Step
    | Scrub Float
    | ShareLink
    | Copied Bool
    | Resized Int
    | MotionChanged Bool
    | ToggleTheme
    | DismissNotice
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlRequested (Browser.Internal url) ->
            -- Plate links change the fragment; anything else (the notices
            -- file) is a real page load.
            if url.path == model.home && url.fragment /= Nothing then
                ( model, Nav.pushUrl model.key (Url.toString url) )

            else
                ( model, Nav.load (Url.toString url) )

        UrlRequested (Browser.External href) ->
            ( model, Nav.load href )

        UrlChanged url ->
            ( route url model, Cmd.none )

        Select i ->
            ( { model | selected = clamp 0 (trainCount model - 1) i, knob = Departure }, Cmd.none )

        SelectKnob i k ->
            ( { model | selected = i, knob = k }, Cmd.none )

        Nudge i k d ->
            ( updateGame (Game.nudge i k d) { model | selected = i, knob = k }, Cmd.none )

        PointerDown grab ->
            let
                lvl =
                    level model

                g =
                    Chart.geometry lvl (chartWidth model.width)

                current =
                    List.drop grab.train (Game.plan (game model))
                        |> List.head
                        |> Maybe.map (Rail.knobValue grab.knob)
                        |> Maybe.withDefault 0

                scale =
                    if grab.width > 0 then
                        g.w / grab.width

                    else
                        1
            in
            ( { model
                | selected = grab.train
                , knob = grab.knob
                , drag =
                    Just
                        { train = grab.train
                        , knob = grab.knob
                        , startX = grab.clientX
                        , scale = scale * Chart.minutesPerUnit g
                        , startValue = current
                        , value = current
                        }
              }
            , Cmd.none
            )

        PointerMove clientX ->
            case ( model.drag, selectedTrain model ) of
                ( Just d, Just train ) ->
                    let
                        ( lo, hi ) =
                            Rail.knobBounds (level model) train d.knob

                        value =
                            clamp lo hi (d.startValue + round ((clientX - d.startX) * d.scale))
                    in
                    ( { model | drag = Just { d | value = value } }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        PointerUp ->
            case model.drag of
                Just d ->
                    if d.value == d.startValue then
                        ( { model | drag = Nothing }, Cmd.none )

                    else
                        ( updateGame (Game.set d.train d.knob d.value) { model | drag = Nothing }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        PointerCancel ->
            ( { model | drag = Nothing }, Cmd.none )

        ChartKey key shift ->
            chartKey key shift model

        Undo ->
            ( updateGame Game.undo model, Cmd.none )

        Redo ->
            ( updateGame Game.redo model, Cmd.none )

        Reset ->
            ( updateGame Game.reset model, Cmd.none )

        TogglePlay ->
            case model.playback of
                Playing ->
                    ( { model | playback = Idle }, Cmd.none )

                _ ->
                    let
                        report =
                            Rail.check (level model) (livePlan model)

                        restart =
                            model.playback == Done || model.cursor >= endTime (level model) report - 0.01
                    in
                    ( { model
                        | playback = Playing
                        , cursor =
                            if restart then
                                0

                            else
                                model.cursor
                        , verdict = Nothing
                      }
                    , Cmd.none
                    )

        Frame delta ->
            let
                lvl =
                    level model

                report =
                    Rail.check lvl (livePlan model)

                end =
                    endTime lvl report

                -- The whole run plays in about nine seconds, whatever the plate.
                next =
                    model.cursor + (delta / 1000) * (end / 9)
            in
            if next >= end then
                finish end model

            else
                ( { model | cursor = next }, Cmd.none )

        Step ->
            let
                lvl =
                    level model

                end =
                    endTime lvl (Rail.check lvl (livePlan model))

                next =
                    toFloat ((floor model.cursor // 10 + 1) * 10)
            in
            if next >= end then
                finish end model

            else
                ( { model | cursor = next }, Cmd.none )

        Scrub t ->
            ( { model | cursor = clamp 0 (toFloat (level model).span) t, playback = Idle }, Cmd.none )

        ShareLink ->
            let
                fragment =
                    Share.encode model.plate (Game.plan (game model))
            in
            ( { model | share = Just fragment, copyState = Nothing }
            , Cmd.batch [ Nav.replaceUrl model.key ("#" ++ fragment), copyLink fragment ]
            )

        Copied ok ->
            ( { model | copyState = Just ok }, Cmd.none )

        Resized w ->
            ( { model | width = w }, Cmd.none )

        MotionChanged reduced ->
            ( { model | reducedMotion = reduced }, Cmd.none )

        ToggleTheme ->
            let
                next =
                    if isDark model then
                        Light

                    else
                        Dark

                updated =
                    { model | theme = next }
            in
            ( updated, Cmd.batch [ setTheme (themeName next), save (encodeSaved updated) ] )

        DismissNotice ->
            ( { model | notice = Nothing }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


isDark : Model -> Bool
isDark model =
    case model.theme of
        Dark ->
            True

        Light ->
            False

        Auto ->
            model.prefersDark


finish : Float -> Model -> ( Model, Cmd Msg )
finish end model =
    let
        lvl =
            level model

        g =
            game model

        report =
            Rail.check lvl (Game.plan g)

        verdict =
            { solved = report.solved
            , waiting = report.waiting
            , moves = Game.moves g
            , fromLink = Game.fromLink g
            }

        better old =
            case old of
                Nothing ->
                    True

                Just r ->
                    report.waiting < r.waiting || (report.waiting == r.waiting && verdict.moves < r.moves)

        records =
            if report.solved && better (Dict.get lvl.id model.records) then
                Dict.insert lvl.id { waiting = report.waiting, moves = verdict.moves } model.records

            else
                model.records

        updated =
            { model | cursor = end, playback = Done, verdict = Just verdict, records = records }
    in
    ( updated
    , if records /= model.records then
        save (encodeSaved updated)

      else
        Cmd.none
    )


chartKey : String -> Bool -> Model -> ( Model, Cmd Msg )
chartKey key shift model =
    let
        step =
            if shift then
                5

            else
                1

        knobList =
            selectedTrain model
                |> Maybe.map (\t -> List.sortBy (Rail.knobStation t) (Rail.knobs t))
                |> Maybe.withDefault [ Departure ]

        moveKnob delta =
            let
                indexed =
                    List.indexedMap Tuple.pair knobList

                current =
                    indexed |> List.filter (\( _, k ) -> k == model.knob) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0

                target =
                    clamp 0 (List.length knobList - 1) (current + delta)
            in
            indexed |> List.filter (\( i, _ ) -> i == target) |> List.head |> Maybe.map Tuple.second |> Maybe.withDefault model.knob
    in
    case key of
        "ArrowLeft" ->
            update (Nudge model.selected model.knob -step) model

        "ArrowRight" ->
            update (Nudge model.selected model.knob step) model

        "ArrowUp" ->
            ( { model | knob = moveKnob -1 }, Cmd.none )

        "ArrowDown" ->
            ( { model | knob = moveKnob 1 }, Cmd.none )

        "Enter" ->
            update TogglePlay model

        _ ->
            case String.toInt key of
                Just n ->
                    if n >= 1 && n <= trainCount model then
                        update (Select (n - 1)) model

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize (\w _ -> Resized w)
        , copied Copied
        , motion MotionChanged
        , Browser.Events.onKeyDown globalKeys
        , case model.playback of
            Playing ->
                if model.reducedMotion then
                    Time.every 700 (\_ -> Step)

                else
                    Browser.Events.onAnimationFrameDelta Frame

            _ ->
                Sub.none
        ]


{-| Undo and redo from anywhere on the page.
-}
globalKeys : Decoder Msg
globalKeys =
    Decode.map4
        (\key ctrl meta shift ->
            let
                command =
                    ctrl || meta
            in
            if command && (key == "z" || key == "Z") && shift then
                Redo

            else if command && (key == "z" || key == "Z") then
                Undo

            else if command && (key == "y" || key == "Y") then
                Redo

            else
                NoOp
        )
        (Decode.field "key" Decode.string)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        (Decode.field "shiftKey" Decode.bool)



-- VIEW


view : Model -> Browser.Document Msg
view model =
    let
        lvl =
            level model

        plan =
            livePlan model

        report =
            Rail.check lvl plan
    in
    { title = "Single Track: plate " ++ Clock.roman lvl.id ++ ", " ++ lvl.title
    , body =
        [ div [ HA.class "page" ]
            [ masthead model
            , plateNav model
            , noticeView model
            , main_ [ HA.class "desk" ]
                [ section [ HA.class "sheet", HA.attribute "aria-labelledby" "plate-title" ]
                    [ plateHead lvl model
                    , chartFigure model lvl report
                    , controls model lvl report
                    , statusView model lvl report
                    , surveyFigure model lvl report
                    ]
                , aside [ HA.class "side" ]
                    [ trainsPanel model lvl plan report
                    , howTo
                    ]
                ]
            , colophon
            ]
        ]
    }


masthead : Model -> Html Msg
masthead model =
    header [ HA.class "masthead" ]
        [ div [ HA.class "masthead-text" ]
            [ p [ HA.class "kicker" ] [ text "A timetable puzzle" ]
            , h1 [] [ text "Single Track" ]
            , p [ HA.class "lede" ] [ text "Run trains on one track without a collision." ]
            ]
        , button
            [ HA.class "theme-toggle"
            , HE.onClick ToggleTheme
            , HA.type_ "button"
            , HA.title
                (if isDark model then
                    "Switch to the paper chart (light)"

                 else
                    "Switch to the cyanotype chart (dark)"
                )
            ]
            [ text
                (if isDark model then
                    "Paper"

                 else
                    "Cyanotype"
                )
            ]
        ]


plateNav : Model -> Html Msg
plateNav model =
    nav [ HA.class "plates", HA.attribute "aria-label" "Plates" ]
        [ ol []
            (List.map
                (\l ->
                    let
                        solved =
                            Dict.member l.id model.records

                        current =
                            l.id == model.plate
                    in
                    li []
                        [ a
                            ([ HA.href ("#p" ++ String.fromInt l.id)
                             , HA.classList [ ( "plate-link", True ), ( "solved", solved ), ( "current", current ) ]
                             , HA.attribute "aria-label"
                                ("Plate "
                                    ++ String.fromInt l.id
                                    ++ ": "
                                    ++ l.title
                                    ++ (if solved then
                                            " (solved)"

                                        else
                                            ""
                                       )
                                )
                             , HA.title l.title
                             ]
                                ++ (if current then
                                        [ HA.attribute "aria-current" "page" ]

                                    else
                                        []
                                   )
                            )
                            [ text (Clock.roman l.id) ]
                        ]
                )
                Levels.all
            )
        ]


noticeView : Model -> Html Msg
noticeView model =
    case model.notice of
        Nothing ->
            text ""

        Just message ->
            div [ HA.class "notice", HA.attribute "role" "status" ]
                [ p [] [ text message ]
                , button [ HA.type_ "button", HE.onClick DismissNotice, HA.class "quiet" ] [ text "Dismiss" ]
                ]


plateHead : Level -> Model -> Html Msg
plateHead lvl model =
    let
        record =
            Dict.get lvl.id model.records
    in
    div [ HA.class "plate-head" ]
        [ p [ HA.class "plate-no" ]
            [ text ("Plate " ++ Clock.roman lvl.id ++ " of " ++ Clock.roman Levels.count)
            , case record of
                Just r ->
                    span [ HA.class "plate-record" ] [ text (" · solved, best " ++ Clock.duration r.waiting ++ " waiting") ]

                Nothing ->
                    text ""
            ]
        , h2 [ HA.id "plate-title" ] [ text lvl.title ]
        , p [ HA.class "brief" ] [ text lvl.brief ]
        ]


chartFigure : Model -> Level -> Report -> Html Msg
chartFigure model lvl report =
    let
        g =
            Chart.geometry lvl (chartWidth model.width)

        cursor =
            if model.playback == Idle && model.cursor == 0 then
                Nothing

            else
                Just model.cursor

        dragging =
            model.drag /= Nothing

        moveHandlers =
            if dragging then
                [ HE.on "pointermove" (Decode.map PointerMove (Decode.field "clientX" Decode.float))
                , HE.on "pointerup" (Decode.succeed PointerUp)
                , HE.on "pointercancel" (Decode.succeed PointerCancel)
                , HE.on "lostpointercapture" (Decode.succeed PointerUp)
                ]

            else
                []
    in
    figure [ HA.class "chart-figure" ]
        [ div
            ([ HA.class "chart-surface"
             , HA.classList [ ( "dragging", dragging ) ]
             , HA.attribute "data-capture" ""
             , HA.tabindex 0
             , HA.attribute "role" "group"
             , HA.attribute "aria-label" "Train graph. Arrow keys adjust the selected knob; up and down move between its stations; number keys pick a train; Enter runs."
             , HA.attribute "aria-describedby" "chart-status"
             , HE.on "pointerdown" pointerDownDecoder
             , HE.preventDefaultOn "keydown" chartKeyDecoder
             ]
                ++ moveHandlers
            )
            [ Chart.view
                { level = lvl
                , report = report
                , selected = model.selected
                , knob = model.knob
                , cursor = cursor
                , geometry = g
                , description = chartDescription lvl report
                }
            ]
        , figcaption [ HA.class "chart-caption" ]
            [ text "Graphic timetable. Time runs left to right; the line runs top to bottom, stations spaced by distance. Each thread is a train." ]
        ]


pointerDownDecoder : Decoder Msg
pointerDownDecoder =
    Decode.map4
        (\grab clientX width button ->
            { grab = grab, clientX = clientX, width = width, button = button }
        )
        (Decode.at [ "target", "dataset", "grab" ] Decode.string)
        (Decode.field "clientX" Decode.float)
        (Decode.at [ "currentTarget", "clientWidth" ] Decode.float)
        (Decode.oneOf [ Decode.field "button" Decode.int, Decode.succeed 0 ])
        |> Decode.andThen
            (\e ->
                case ( Chart.parseGrab e.grab, e.button ) of
                    ( Just ( train, knob ), 0 ) ->
                        Decode.succeed (PointerDown { train = train, knob = knob, clientX = e.clientX, width = e.width })

                    _ ->
                        Decode.fail "not a grab"
            )


chartKeyDecoder : Decoder ( Msg, Bool )
chartKeyDecoder =
    Decode.map4
        (\key shift ctrl meta ->
            ( key, shift, ctrl || meta )
        )
        (Decode.field "key" Decode.string)
        (Decode.field "shiftKey" Decode.bool)
        (Decode.field "ctrlKey" Decode.bool)
        (Decode.field "metaKey" Decode.bool)
        |> Decode.andThen
            (\( key, shift, command ) ->
                if command then
                    Decode.fail "command key"

                else if List.member key [ "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter" ] || String.toInt key /= Nothing then
                    Decode.succeed ( ChartKey key shift, True )

                else
                    Decode.fail "not ours"
            )


chartDescription : Level -> Report -> String
chartDescription lvl report =
    "Train graph for plate "
        ++ String.fromInt lvl.id
        ++ ": "
        ++ String.fromInt (List.length lvl.trains)
        ++ " trains, "
        ++ String.fromInt (Array.length lvl.stations)
        ++ " stations, "
        ++ String.fromInt (List.length report.conflicts)
        ++ " conflicts."


controls : Model -> Level -> Report -> Html Msg
controls model lvl report =
    let
        g =
            game model

        playLabel =
            case model.playback of
                Playing ->
                    "Pause"

                Done ->
                    "Run again"

                Idle ->
                    if model.cursor > 0 then
                        "Resume"

                    else
                        "Run"
    in
    div [ HA.class "controls" ]
        [ div [ HA.class "control-row" ]
            [ button [ HA.type_ "button", HA.class "primary", HE.onClick TogglePlay ] [ text playLabel ]
            , label [ HA.class "scrub" ]
                [ span [ HA.class "scrub-label" ] [ text ("Chart time " ++ Clock.time lvl.clock (round model.cursor)) ]
                , input
                    [ HA.type_ "range"
                    , HA.min "0"
                    , HA.max (String.fromInt lvl.span)
                    , HA.step "1"
                    , HA.value (String.fromInt (round model.cursor))
                    , HE.onInput (String.toFloat >> Maybe.map Scrub >> Maybe.withDefault NoOp)
                    ]
                    []
                ]
            ]
        , knobBar model lvl
        , div [ HA.class "control-row" ]
            [ button [ HA.type_ "button", HE.onClick Undo, HA.disabled (not (Game.canUndo g)), HA.title "Undo (Ctrl+Z)" ] [ text "Undo" ]
            , button [ HA.type_ "button", HE.onClick Redo, HA.disabled (not (Game.canRedo g)), HA.title "Redo (Ctrl+Shift+Z)" ] [ text "Redo" ]
            , button [ HA.type_ "button", HE.onClick Reset, HA.disabled (Game.plan g == Rail.initialPlan lvl) ] [ text "Reset" ]
            , button [ HA.type_ "button", HE.onClick ShareLink ] [ text "Share timetable" ]
            ]
        , shareView model
        , verdictView model lvl report
        ]


{-| The selected knob, adjustable right under the chart (handy on phones,
where the train cards are further down).
-}
knobBar : Model -> Level -> Html Msg
knobBar model lvl =
    case ( selectedTrain model, List.drop model.selected (livePlan model) |> List.head ) of
        ( Just t, Just tp ) ->
            let
                value =
                    Rail.knobValue model.knob tp

                ( lo, hi ) =
                    Rail.knobBounds lvl t model.knob

                station =
                    stationName lvl (Rail.knobStation t model.knob)

                ( what, shown ) =
                    case model.knob of
                        Departure ->
                            ( "leaves " ++ station, Clock.time lvl.clock value )

                        Dwell _ ->
                            ( "waits at " ++ station, Clock.duration value )
            in
            div [ HA.class ("control-row knob-bar ink-" ++ String.fromInt t.ink) ]
                [ span [ HA.class "swatch", HA.attribute "aria-hidden" "true" ] []
                , span [ HA.class "knob-bar-name" ] [ strong [] [ text t.name ], text (" " ++ what) ]
                , span [ HA.class "stepper" ]
                    [ button [ HA.type_ "button", HE.onClick (Nudge model.selected model.knob -1), HA.disabled (value <= lo), HA.attribute "aria-label" (t.name ++ " " ++ what ++ ": one minute less") ] [ text "−" ]
                    , Html.output [ HA.attribute "aria-live" "polite" ] [ text shown ]
                    , button [ HA.type_ "button", HE.onClick (Nudge model.selected model.knob 1), HA.disabled (value >= hi), HA.attribute "aria-label" (t.name ++ " " ++ what ++ ": one minute more") ] [ text "+" ]
                    ]
                ]

        _ ->
            text ""


shareView : Model -> Html Msg
shareView model =
    case model.share of
        Nothing ->
            text ""

        Just fragment ->
            div [ HA.class "share" ]
                [ label []
                    [ span []
                        [ text
                            (case model.copyState of
                                Just True ->
                                    "Link copied. It opens this plate with your timetable:"

                                Just False ->
                                    "Copy this link to share your timetable:"

                                Nothing ->
                                    "Link to your timetable:"
                            )
                        ]
                    , input [ HA.readonly True, HA.value ("#" ++ fragment), HA.class "share-link", HA.attribute "aria-label" "Share link fragment" ] []
                    ]
                ]


verdictView : Model -> Level -> Report -> Html Msg
verdictView model lvl report =
    case ( model.playback, model.verdict ) of
        ( Done, Just v ) ->
            if v.solved then
                div [ HA.class "stamp", HA.attribute "role" "status" ]
                    [ p [ HA.class "stamp-head" ] [ text "Passed" ]
                    , p [ HA.class "stamp-body" ]
                        [ text
                            (Clock.duration v.waiting
                                ++ " waiting · par "
                                ++ Clock.duration lvl.par
                                ++ (if v.fromLink && v.moves == 0 then
                                        " · shared timetable"

                                    else
                                        " · " ++ String.fromInt v.moves ++ plural v.moves " move" " moves"
                                   )
                            )
                        ]
                    , p [ HA.class "stamp-note" ]
                        [ text
                            (if v.waiting < lvl.par then
                                "Under par. That beats the designer's best."

                             else if v.waiting == lvl.par then
                                "At par."

                             else
                                "Solved. Par is lower: can you trim the waiting?"
                            )
                        ]
                    , if lvl.id < Levels.count then
                        a [ HA.href ("#p" ++ String.fromInt (lvl.id + 1)), HA.class "next-plate" ] [ text ("On to plate " ++ Clock.roman (lvl.id + 1)) ]

                      else
                        p [ HA.class "stamp-note" ] [ text "That was the last plate." ]
                    ]

            else
                div [ HA.class "stamp failed", HA.attribute "role" "status" ]
                    [ p [ HA.class "stamp-head" ]
                        [ text
                            (if List.isEmpty report.conflicts then
                                "Late"

                             else
                                "Collision"
                            )
                        ]
                    , p [ HA.class "stamp-body" ] [ text "Not yet. Adjust the timetable and run it again." ]
                    ]

        _ ->
            text ""


plural : Int -> String -> String -> String
plural n one many =
    if n == 1 then
        one

    else
        many


statusView : Model -> Level -> Report -> Html Msg
statusView model lvl report =
    let
        g =
            game model

        conflictLines =
            List.map (describeConflict lvl) report.conflicts

        lateLines =
            List.map2 Tuple.pair lvl.trains report.runs
                |> List.filter (\( t, r ) -> r.arrival > t.due)
                |> List.map
                    (\( t, r ) ->
                        "The "
                            ++ t.name
                            ++ " reaches "
                            ++ stationName lvl t.to
                            ++ " at "
                            ++ Clock.time lvl.clock r.arrival
                            ++ ", "
                            ++ Clock.duration (r.arrival - t.due)
                            ++ " late."
                    )

        headline =
            if not (List.isEmpty report.conflicts) then
                String.fromInt (List.length report.conflicts) ++ plural (List.length report.conflicts) " conflict" " conflicts"

            else if not (List.isEmpty lateLines) then
                "No collisions, but " ++ String.fromInt (List.length lateLines) ++ plural (List.length lateLines) " train is late" " trains are late"

            else
                "Line clear. Every train on time."

        shown =
            List.take 4 (conflictLines ++ lateLines)

        more =
            List.length conflictLines + List.length lateLines - List.length shown
    in
    div [ HA.class "status", HA.id "chart-status" ]
        [ div [ HA.class "tally" ]
            [ tally "Moves" (String.fromInt (Game.moves g))
            , tally "Waiting" (Clock.duration report.waiting)
            , tally "Par" (Clock.duration lvl.par)
            ]
        , p
            [ HA.classList [ ( "headline", True ), ( "alarm", not report.solved ), ( "clear", report.solved ) ]
            , HA.attribute "aria-live" "polite"
            ]
            [ text headline
            , if report.solved && model.playback /= Done then
                text " Press Run to dispatch."

              else
                text ""
            ]
        , if List.isEmpty shown then
            text ""

          else
            ul [ HA.class "log" ]
                (List.map (\line -> li [] [ text line ]) shown
                    ++ (if more > 0 then
                            [ li [] [ text ("and " ++ String.fromInt more ++ " more.") ] ]

                        else
                            []
                       )
                )
        ]


tally : String -> String -> Html msg
tally name value =
    dl [ HA.class "tally-item" ] [ dt [] [ text name ], dd [] [ text value ] ]


stationName : Level -> Int -> String
stationName lvl i =
    Array.get i lvl.stations |> Maybe.map .name |> Maybe.withDefault "?"


trainName : Level -> Int -> String
trainName lvl i =
    List.drop i lvl.trains |> List.head |> Maybe.map .name |> Maybe.withDefault "?"


describeConflict : Level -> Conflict -> String
describeConflict lvl c =
    let
        names =
            List.map (trainName lvl) c.trains

        joined =
            case List.reverse names of
                lastName :: rest ->
                    if List.isEmpty rest then
                        lastName

                    else
                        String.join ", " (List.reverse rest) ++ " and " ++ lastName

                [] ->
                    ""

        at =
            Clock.time lvl.clock (round c.time)
    in
    case ( c.kind, c.place ) of
        ( HeadOn, Section s ) ->
            "Head-on: " ++ joined ++ " meet between " ++ stationName lvl s ++ " and " ++ stationName lvl (s + 1) ++ " at " ++ at ++ "."

        ( RearEnd, Section s ) ->
            "Rear-end: " ++ joined ++ " are on the section from " ++ stationName lvl s ++ " to " ++ stationName lvl (s + 1) ++ " together, around " ++ at ++ "."

        ( _, AtStation s ) ->
            let
                tracks =
                    Array.get s lvl.stations |> Maybe.map .tracks |> Maybe.withDefault 1
            in
            "Crowded: "
                ++ joined
                ++ " are at "
                ++ stationName lvl s
                ++ " at once around "
                ++ Clock.time lvl.clock c.from
                ++ ", but it has "
                ++ String.fromInt tracks
                ++ plural tracks " track." " tracks."

        ( _, Section s ) ->
            joined ++ " conflict between " ++ stationName lvl s ++ " and " ++ stationName lvl (s + 1) ++ "."


surveyFigure : Model -> Level -> Report -> Html Msg
surveyFigure model lvl report =
    figure [ HA.class "survey-figure" ]
        [ Survey.view
            { level = lvl
            , runs = report.runs
            , conflicts = report.conflicts
            , cursor = model.cursor
            , width = chartWidth model.width
            }
        , figcaption [ HA.class "chart-caption" ] [ text "The line as surveyed, with each train where it stands at the chart time." ]
        ]


trainsPanel : Model -> Level -> Plan -> Report -> Html Msg
trainsPanel model lvl plan report =
    section [ HA.class "trains", HA.attribute "aria-labelledby" "trains-title" ]
        [ h3 [ HA.id "trains-title" ] [ text "Trains" ]
        , Html.Keyed.ol [ HA.class "train-list" ]
            (List.map3
                (\( i, t ) tp run ->
                    ( String.fromInt lvl.id ++ "-" ++ String.fromInt i
                    , trainCard model lvl i t tp run
                    )
                )
                (List.indexedMap Tuple.pair lvl.trains)
                plan
                report.runs
            )
        ]


trainCard : Model -> Level -> Int -> Rail.Train -> Rail.TrainPlan -> Rail.Run -> Html Msg
trainCard model lvl i t tp run =
    let
        selected =
            i == model.selected

        late =
            run.arrival > t.due

        speedName =
            if t.speed >= 60 then
                "express, 60 km/h"

            else if t.speed >= 40 then
                "stopping, 40 km/h"

            else
                "goods, 30 km/h"

        callNote =
            if t.call > 0 then
                ", calls " ++ Clock.duration t.call ++ " at each stop"

            else
                ""

        stopStations =
            List.map (\k -> ( k, Rail.knobStation t k )) (Rail.knobs t)

        knobRow ( k, st ) =
            let
                value =
                    Rail.knobValue k tp

                ( lo, hi ) =
                    Rail.knobBounds lvl t k

                ( what, shown ) =
                    case k of
                        Departure ->
                            ( "Leaves " ++ stationName lvl st, Clock.time lvl.clock value )

                        Dwell _ ->
                            ( "Waits at " ++ stationName lvl st, Clock.duration value )

                active =
                    selected && k == model.knob
            in
            li [ HA.classList [ ( "knob-row", True ), ( "active", active ) ] ]
                [ span [ HA.class "knob-name" ] [ text what ]
                , span [ HA.class "stepper" ]
                    [ button
                        [ HA.type_ "button"
                        , HE.onClick (Nudge i k -1)
                        , HA.disabled (value <= lo)
                        , HA.attribute "aria-label" (what ++ ": one minute less")
                        ]
                        [ text "−" ]
                    , Html.output [ HA.attribute "aria-live" "off" ] [ text shown ]
                    , button
                        [ HA.type_ "button"
                        , HE.onClick (Nudge i k 1)
                        , HA.disabled (value >= hi)
                        , HA.attribute "aria-label" (what ++ ": one minute more")
                        ]
                        [ text "+" ]
                    ]
                ]
    in
    li [ HA.class ("train ink-" ++ String.fromInt t.ink), HA.classList [ ( "selected", selected ), ( "late", late ) ] ]
        [ button
            [ HA.type_ "button"
            , HA.class "train-pick"
            , HE.onClick (Select i)
            , HA.attribute "aria-pressed"
                (if selected then
                    "true"

                 else
                    "false"
                )
            ]
            [ span [ HA.class ("swatch ink-" ++ String.fromInt t.ink), HA.attribute "aria-hidden" "true" ] []
            , span [ HA.class "train-name" ] [ kbd [] [ text (String.fromInt (i + 1)) ], text (" " ++ t.name) ]
            , span [ HA.class "train-route" ] [ text (stationName lvl t.from ++ " to " ++ stationName lvl t.to) ]
            ]
        , p [ HA.class "train-facts" ]
            [ text (speedName ++ callNote ++ ". Ready " ++ Clock.time lvl.clock t.ready ++ ", due " ++ Clock.time lvl.clock t.due ++ ".") ]
        , p [ HA.classList [ ( "arrival", True ), ( "is-late", late ) ] ]
            [ text
                ("Arrives "
                    ++ Clock.time lvl.clock run.arrival
                    ++ (if late then
                            ", " ++ Clock.duration (run.arrival - t.due) ++ " late"

                        else
                            ", on time"
                       )
                )
            ]
        , if selected then
            ul [ HA.class "knobs" ] (List.map knobRow stopStations)

          else
            text ""
        ]


howTo : Html msg
howTo =
    section [ HA.class "howto", HA.attribute "aria-labelledby" "howto-title" ]
        [ h3 [ HA.id "howto-title" ] [ text "Reading the chart" ]
        , ul []
            [ li [] [ strong [] [ text "Threads are trains. " ], text "Steep means fast; a flat stretch is a train waiting at a station." ]
            , li [] [ strong [] [ text "One track. " ], text "Two trains can never be on the same section at once, so they meet or overtake only at stations." ]
            , li [] [ strong [] [ text "Double rules are loops " ], text "with two tracks; a dashed rule is a halt with one; a yard has three." ]
            , li [] [ strong [] [ text "Red cross-hatching " ], text "marks a conflict. A small hooked tick on a train's last station is its deadline." ]
            , li [] [ strong [] [ text "To edit, " ], text "drag a thread sideways to change when it leaves, or drag a round knob to change a wait. The steppers in each train's card do the same." ]
            , li [] [ strong [] [ text "Keys: " ], kbd [] [ text "1" ], text "–", kbd [] [ text "6" ], text " pick a train, ", kbd [] [ text "←" ], kbd [] [ text "→" ], text " adjust (hold Shift for 5 min), ", kbd [] [ text "↑" ], kbd [] [ text "↓" ], text " move between its stations, ", kbd [] [ text "Enter" ], text " runs, ", kbd [] [ text "Ctrl" ], text "+", kbd [] [ text "Z" ], text " undoes." ]
            , li [] [ strong [] [ text "Score. " ], text "Waiting is every minute a train spends beyond its earliest start and required stops. Par is the least waiting our design-time search found; it may be beatable." ]
            ]
        ]


colophon : Html msg
colophon =
    footer [ HA.class "colophon" ]
        [ p []
            [ text "Single Track is a portfolio piece by Ramen Protocol, written in Elm. Lines, stations and speeds are invented. Built with AI assistance (Claude). MIT licence; "
            , a [ HA.href "THIRD-PARTY-NOTICES.txt" ] [ text "third-party notices" ]
            , text "."
            ]
        , p [] [ text "Style after the graphic train timetables of the 1880s, where time runs across and the line runs down." ]
        ]



-- MAIN


main : Program Decode.Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }
