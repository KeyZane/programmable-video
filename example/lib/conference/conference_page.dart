import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twilio_unofficial_programmable_video_example/conference/conference_button_bar.dart';
import 'package:twilio_unofficial_programmable_video_example/conference/participant_model.dart';
import 'package:twilio_unofficial_programmable_video_example/room/room_model.dart';
import 'package:twilio_unofficial_programmable_video_example/shared/services/platform_service.dart';
import 'package:twilio_unofficial_programmable_video_example/shared/widgets/noise_box.dart';
import 'package:twilio_unofficial_programmable_video_example/shared/widgets/platform_alert_dialog.dart';
import 'package:twilio_unofficial_programmable_video_example/shared/widgets/responsive_save_area.dart';
import 'package:twilio_unofficial_programmable_video/twilio_unofficial_programmable_video.dart';
import 'package:wakelock/wakelock.dart';

class ConferencePage extends StatefulWidget {
  final RoomModel roomModel;

  const ConferencePage({
    Key key,
    @required this.roomModel,
  }) : super(key: key);

  @override
  _ConferencePageState createState() => _ConferencePageState();
}

class _ConferencePageState extends State<ConferencePage> {
  bool _videoEnabled = true;
  bool _microphoneEnabled = false; // TODO(AS): Enable audio again...
  double _top;
  double _right = 10;
  double _bottom = 80;
  double _left;

  LocalVideoTrack _localVideoTrack;
  Room _room;
  String _deviceId;

  final List<Participant> _participants = [];
  final Duration _duration300ms = const Duration(milliseconds: 300);
  final Duration _duration0ms = const Duration(milliseconds: 0);
  Duration _duration;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _duration = _duration300ms;
    _wakeLock(true);
    _getDeviceId();
    _connectToRoom();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _wakeLock(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: null,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ResponsiveSafeArea(
          builder: (BuildContext context, Size size) {
            return Stack(
              children: <Widget>[
                _buildParticipants(context, size),
                ConferenceButtonBar(
                  videoEnabled: _videoEnabled,
                  microphoneEnabled: _microphoneEnabled,
                  onVideoEnabled: _onVideoEnabled,
                  onMicrophoneEnabled: _onMicrophoneEnabled,
                  onHangup: _onHangup,
                  onSwitchCamera: _onSwitchCamera,
                  onPersonAdd: _onPersonAdd,
                  onShow: _onShowBar,
                  onHide: _onHideBar,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _getDeviceId() async {
    try {
      _deviceId = await PlatformService.deviceId;
    } catch (err) {
      print(err);
      _deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> _connectToRoom() async {
    try {
      _localVideoTrack = LocalVideoTrack(true, VideoCapturer.FRONT_CAMERA);
      var connectOptions = ConnectOptions(widget.roomModel.token)
        ..roomName(widget.roomModel.name)
        ..preferAudioCodecs([OpusCodec()])
        ..audioTracks([LocalAudioTrack(_microphoneEnabled)])
        ..videoTracks([_localVideoTrack]);

      _room = await TwilioUnofficialProgrammableVideo.connect(connectOptions);

      _room.onConnected.listen(_onConnected);
      _room.onParticipantConnected.listen(_onParticipantConnected);
      _room.onParticipantDisconnected.listen(_onParticipantDisconnected);
      _room.onConnectFailure.listen(_onConnectFailure);
    } catch (err) {
      print(err);
    }
  }

  Participant _buildParticipant({Widget child, bool isRemote = true, String id}) {
    return Participant(
      id: id,
      isRemote: isRemote,
      widget: Stack(
        children: <Widget>[child],
      ),
    );
  }

  void _onConnected(RoomEvent roomEvent) {
    setState(() {
      _participants.add(_buildParticipant(child: _localVideoTrack.widget(), isRemote: false, id: _deviceId));
      for (final RemoteParticipant remoteParticipant in roomEvent.room.remoteParticipants) {
        remoteParticipant.onVideoTrackSubscribed.listen(_onVideoTrackSubscribed);
        remoteParticipant.onVideoTrackUnsubscribed.listen(_onVideoTrackUnSubscribed);

        for (final RemoteVideoTrackPublication remoteVideoTrackPublication in remoteParticipant.remoteVideoTracks) {
          if (remoteVideoTrackPublication.isTrackSubscribed) {
            _participants.add(
              _buildParticipant(child: remoteVideoTrackPublication.remoteVideoTrack.widget(), id: remoteParticipant.sid),
            );
          }
        }
      }
    });
  }

  void _onParticipantConnected(RoomEvent roomEvent) {
    roomEvent.remoteParticipant.onVideoTrackSubscribed.listen(_onVideoTrackSubscribed);
    roomEvent.remoteParticipant.onVideoTrackUnsubscribed.listen(_onVideoTrackUnSubscribed);
  }

  void _onParticipantDisconnected(RoomEvent roomEvent) {
    print('Participants in the room:');
    for (Participant p in _participants) {
      print(' - ${p.id}');
    }
    print('Participant leaving: ${roomEvent.remoteParticipant.sid}');
    setState(() {
      _participants.removeWhere((Participant p) => p.id == roomEvent.remoteParticipant.sid);
    });
  }

  void _onConnectFailure(RoomEvent roomEvent) {
    print('ConnectFailure: ${roomEvent.exception}');
  }

  void _onVideoTrackSubscribed(RemoteParticipantEvent remoteParticipantEvent) {
    setState(() {
      _participants.add(_buildParticipant(
        child: remoteParticipantEvent.remoteVideoTrack.widget(),
        id: remoteParticipantEvent.remoteParticipant.sid, // TODO(AS): Has to be refactored to use 'participant.sid'
      ));
    });
  }

  void _onVideoTrackUnSubscribed(RemoteParticipantEvent remoteParticipantEvent) {
    print('VideoTrackUnsubscribed, ${remoteParticipantEvent.remoteParticipant.sid}, ${remoteParticipantEvent.remoteVideoTrack.sid}');
  }

  void _onVideoEnabled() {
    setState(() {
      _videoEnabled = !_videoEnabled;
    });
    print('onVideoEnabled: $_videoEnabled');
  }

  void _onMicrophoneEnabled() {
    setState(() {
      _microphoneEnabled = !_microphoneEnabled;
    });
    print('onMicrophoneEnabled: $_microphoneEnabled');
  }

  void _onHangup() {
    print('onHangup');
    setState(() {
      if (_participants.length == 1) {
        Navigator.of(context).pop();
      } else {
        _participants.removeAt(0);
      }
    });
  }

  void _onSwitchCamera() {
    print('onSwitchCamera');
  }

  void _onPersonAdd() {
    setState(() {
      if (_participants.length < 18) {
        _participants.insert(
          0,
          Participant(
            id: (_participants.length + 1).toString(),
            widget: Stack(
              children: <Widget>[
                const Placeholder(),
                Center(
                  child: Text(
                    (_participants.length + 1).toString(),
                    style: const TextStyle(
                      shadows: <Shadow>[
                        Shadow(
                          blurRadius: 3.0,
                          color: Color.fromARGB(255, 0, 0, 0),
                        ),
                        Shadow(
                          blurRadius: 8.0,
                          color: Color.fromARGB(255, 255, 255, 255),
                        ),
                      ],
                      fontSize: 80,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        PlatformAlertDialog(
          title: 'Maximum reached',
          content: 'There is a room limit of 18 participants',
          defaultActionText: 'OK',
        ).show(context);
      }
    });
  }

  Widget _buildParticipants(BuildContext context, Size size) {
    final List<Widget> children = <Widget>[];

    if (_participants.length <= 2) {
      _buildOverlayLayout(context, size, children);
      return Stack(children: children);
    }

    void buildInCols(bool removeLocalBeforeChunking, int columns) {
      _buildLayoutInGrid(context, size, children, removeLocalBeforeChunking: removeLocalBeforeChunking, columns: columns);
    }

    if (_participants.length <= 3) {
      buildInCols(true, 1);
    } else if (_participants.length <= 6 || _participants.length == 8) {
      buildInCols(false, 2);
    } else if (_participants.length == 7 || _participants.length == 9) {
      buildInCols(true, 2);
    } else if (_participants.length == 13 || _participants.length == 16) {
      buildInCols(true, 3);
    } else if (_participants.length <= 18) {
      buildInCols(false, 3);
    }

    return Column(
      children: children,
    );
  }

  void _buildOverlayLayout(BuildContext context, Size size, List<Widget> children) {
    double statusBarHeight = MediaQuery.of(context).padding.top;
    print('statusBarHeight: $statusBarHeight');

    if (_participants.isEmpty) {
      children.add(Container(
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ));
      return;
    }
    if (_participants.length == 1) {
      children.add(_buildNoiseBox());
    } else {
      final Participant remoteParticipant = _participants.firstWhere((Participant participant) => participant.isRemote, orElse: () => null);
      if (remoteParticipant != null) {
        children.add(remoteParticipant.widget);
      }
    }

    final Participant localParticipant = _participants.firstWhere((Participant participant) => !participant.isRemote, orElse: () => null);
    if (localParticipant != null) {
      final double width = size.width * 0.25;
      final double height = width * (size.height / size.width);

      Widget clippedVideo = Container(
        width: width,
        height: height,
        child: ClipRRect(
          child: localParticipant.widget,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
        ),
      );

//      children.add(
//        Positioned(
//          width: size.width / 2,
//          height: size.height / 2,
//          top: 0,
//          left: 0,
//          child: DragTarget(
//            builder: (BuildContext context, List candidateData, List rejectedData) {
//              return Container();
//            },
//            onWillAccept: (_) {
//              print('DragTarget.onWillAccept');
//              return true;
//            },
//            onAccept: (_) {
//              print('DragTarget.onAccept');
//            },
//            onLeave: (_) => print('DragTarget.onLeave'),
//          ),
//        ),
//      );
      children.add(
        AnimatedPositioned(
          top: _top,
          right: _right,
          bottom: _bottom,
          left: _left,
          width: width,
          height: height,
          child: Draggable(
            child: clippedVideo,
            feedback: clippedVideo,
            childWhenDragging: Container(),
            onDragCompleted: () {
              print('Draggable.onDragCompleted');
            },
            onDraggableCanceled: (_, __) => print('Draggable.onDragCanceled'),
            onDragEnd: (DraggableDetails details) {
              //if (details.wasAccepted) {
              print('Draggable.onDragEnd, details.offset => ${details.offset}');
              _top = statusBarHeight - details.offset.dy;
              _left = details.offset.dx;
              _bottom = null;
              _right = null;
              setState(() {});
              //}
            },
            onDragStarted: () {
              print('Draggable.onDragStarted => Set animation duration to 0ms');
              _duration = _duration0ms;
            },
          ),
          duration: _duration,
        ),
      );
    }
  }

  void _buildLayoutInGrid(BuildContext context, Size size, List<Widget> children, {bool removeLocalBeforeChunking = false, int columns = 2}) {
    Participant localParticipant;
    if (removeLocalBeforeChunking) {
      localParticipant = _participants.firstWhere((Participant participant) => !participant.isRemote, orElse: () => null);
      if (localParticipant != null) {
        _participants.remove(localParticipant);
      }
    }
    final List<List<Participant>> chunkedParticipants = chunk(array: _participants, size: columns);
    if (localParticipant != null) {
      chunkedParticipants.last.add(localParticipant);
      _participants.add(localParticipant);
    }

    for (final List<Participant> participantChunk in chunkedParticipants) {
      final List<Widget> rowChildren = <Widget>[];
      for (final Participant participant in participantChunk) {
        rowChildren.add(
          Container(
            width: size.width / participantChunk.length,
            child: participant.widget,
          ),
        );
      }
      children.add(
        Container(
          height: size.height / chunkedParticipants.length,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: rowChildren,
          ),
        ),
      );
    }
  }

  NoiseBox _buildNoiseBox() {
    return NoiseBox(
      density: NoiseBoxDensity.xLow,
      backgroundColor: Colors.grey.shade900,
      child: Center(
        child: Container(
          color: Colors.black54,
          width: double.infinity,
          height: 40,
          child: Center(
            child: Text(
              'Waiting for another participant to connect to the room...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  List<List<T>> chunk<T>({@required List<T> array, @required int size}) {
    final List<List<T>> result = <List<T>>[];
    if (array.isEmpty || size <= 0) {
      return result;
    }
    int first = 0;
    int last = size;
    final int totalLoop = array.length % size == 0 ? array.length ~/ size : array.length ~/ size + 1;
    for (int i = 0; i < totalLoop; i++) {
      if (last > array.length) {
        result.add(array.sublist(first, array.length));
      } else {
        result.add(array.sublist(first, last));
      }
      first = last;
      last = last + size;
    }
    return result;
  }

  void _onShowBar() {
    setState(() {
      _bottom = 80;
    });
  }

  void _onHideBar() {
    setState(() {
      _bottom = 10;
    });
  }

  Future<void> _wakeLock(bool enable) async {
    return await (enable ? Wakelock.enable() : Wakelock.disable());
  }
}