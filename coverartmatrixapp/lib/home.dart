import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:uni_links/uni_links.dart';
import 'package:url_launcher/url_launcher.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {

  int brightnessVal = 100;
  String? loginname, redirurl;
  String pi_ip = "192.168.0.21";
  bool ip_ok = true;
  late Socket socket;
  late TextEditingController ipController;
  late StreamSubscription? sub;
  void socketListenTo([Function(String)? fn]) {
    socket.listen(
          (Uint8List data) {
        final serverResponse = String.fromCharCodes(data);
        print("Server says: $serverResponse");
        if (fn != null) fn(serverResponse);
      },
      onError: (error) {
        print(error);
        socket.destroy();
      },
      onDone: () {
        print("Server left.");
        socket.destroy();
      },
    );
  }
  void socketListen() => socketListenTo();
  get loggedin => loginname != null;

  Future<void> initSocket() async {
    socket = await Socket.connect(pi_ip, 9999);
    print("Connected to: ${socket.remoteAddress.address}:${socket.remotePort}");
  }

  void sendMessage(Socket socket, String message) {
    print("Client: $message");
    socket.write(message);
  }

  @override
  void initState() {
    super.initState();
    ipController = TextEditingController(text: pi_ip);
    handleIncomingLinks();
  }

  @override
  void dispose() {
    ipController.dispose();
    sub?.cancel();
    super.dispose();
  }

  void handleIncomingLinks() {
    sub = linkStream.listen((String? url) {
      print("got incoming url: $url");
      setState(() {
        redirurl = url;
      });
    }, onError: (Object err) {
      print("error getting incoming url: $err");
      setState(() {
        redirurl = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    print(loggedin ? "logged in" : "not logged in");
    return Scaffold(
      appBar: AppBar(
        title: const Text("Coverart Matrix"),
        centerTitle: true,
        backgroundColor: Colors.green[600],
      ),
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 5),
              TextField(
                controller: ipController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Pi IP",
                  errorText: ip_ok ? null : "Not a valid IP address",
                ),
                onChanged: (value) {
                  setState(() {
                    ip_ok = validateIP(value);
                    if (ip_ok) pi_ip = value;
                  });
                },
              ),
              loggedin ? logoutRow() : loginButton(),
              const Divider(height: 50),
              const Text("Power"),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  powerButton("on"),
                  powerButton("off"),
                ],
              ),
              const Divider(height: 50),
              const Text("Brightness"),
              Slider(
                value: brightnessVal.toDouble(),
                max: 100,
                min: 0,
                divisions: 100,
                label: brightnessVal.toString(),
                onChanged: (value) {
                  setState(() {
                    brightnessVal = value.toInt();
                  });
                },
              ),
              ElevatedButton(
                onPressed: () async {
                  print(await setStatus("brightness", brightnessVal.toString()));
                },
                child: const Text("Save brightness"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ElevatedButton powerButton(String setTo) {
    return ElevatedButton(
      onPressed: () async {
        print(await setStatus("power", setTo));
      },
      child: Text("Turn $setTo"),
    );
  }

  Future<String> setStatus(String property, String value) async {
    final response = await http.post(
      Uri.parse('https://web.djkhas.com/coverart/setstatus.php'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'property': property,
        'value': value,
      }),
    );
    if (response.statusCode != 204) {
      // error handling
      return response.body;
    } else {
      return "success";
    }
  }

  bool validateIP(String ip) {
    if (ip == "localhost") return true;
    List<String> parts = ip.split('.');
    if (parts.length != 4) return false;
    for (var element in parts) {
      int? x = int.tryParse(element);
      if (x == null) {
        return false;
      } else if (x < 0 || x > 255) {
        return false;
      }
    }
    return true;
  }

  void setLoginName(String response, [bool cached = false]) {
    setState(() {
      if (cached) {
        loginname = response.substring(7); // `CACHED:`
      } else {
        loginname = response.substring(9); // `LOGGEDIN:`
      }
    });
  }

  ElevatedButton loginButton() {
    return ElevatedButton(
      onPressed: ip_ok ? () async {
        print(await setStatus("req_login", "1"));
        await initSocket();
        socketListenTo((response) async {
          if (response.startsWith("CACHED")) {
            // TODO: LOGGED IN
            print("CACHED LOGIN SUCCESS!!!");
            setLoginName(response, true);
          } else {
            if (await getRedirUrl(response)) {
              Future.delayed(const Duration(milliseconds: 100), () async {
                await initSocket();
                socketListenTo((response2) {
                  if (response2.startsWith("LOGGEDIN")) {
                    // TODO: LOGGED IN
                    print("LOGIN SUCCESS!!!");
                    setLoginName(response2);
                  } else {
                    // TODO: LOGIN FAILED
                    print("Login failed :(");
                  }
                  redirurl = null;
                });
                sendMessage(socket, "REDIR:$redirurl");
              });
            } else {
              print("LOGIN FAIL: Could not get redirect url");
            }
          }
        });
        sendMessage(socket, "LOGIN");
      } : null,
      child: const Text("Login to Spotify"),
    );
  }

  Future<bool> getRedirUrl(String authUrl) async {
    if (await canLaunch(authUrl)) {
      await launch(authUrl);
      while (redirurl == null) {
        print("waiting for redirurl to not be null");
        await Future.delayed(const Duration(milliseconds: 100));
      }
      print("found redirurl: $redirurl");
      return true;
    } else {
      print("Could not open authorize URL");
      return false;
    }
  }

  Row logoutRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Card(
          color: Colors.green[600],
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const FaIcon(FontAwesomeIcons.spotify, color: Colors.white),
                const SizedBox(width: 8),
                Text(loginname!, style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                )),
              ],
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            print(await setStatus("req_login", "-1"));
            setState(() {
              loginname = null;
            });
          },
          child: const Text("Logout"),
        )
      ],
    );
  }

}
