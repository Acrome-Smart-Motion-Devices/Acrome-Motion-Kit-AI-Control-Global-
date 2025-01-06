import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io';

void main() => runApp(MyApp());

String selectedIp = '';  // Başlangıçta boş bir IP adresi seçilecek.
bool isContinueButtonVisible = false;
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: IPScanner(),
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
    );
  }
}

class IPScanner extends StatefulWidget {
  @override
  _IPScannerState createState() => _IPScannerState();
}

class _IPScannerState extends State<IPScanner> {
  final NetworkInfo _networkInfo = NetworkInfo();
  String? subnetAddress;
  List<Map<String, String>> devices = [];
  bool isScanning = false;

  Future<void> scanNetwork() async {
    setState(() {
      isScanning = true;
      devices.clear();
    });

    final ipAddress = await _networkInfo.getWifiIP();
    if (ipAddress != null) {
      final subnet = ipAddress.substring(0, ipAddress.lastIndexOf('.'));
      subnetAddress = subnet;

      List<Future> pingTasks = [];
      for (int i = 1; i < 255; i++) {
        final targetIp = '$subnet.$i';
        pingTasks.add(_scanLinuxDevice(targetIp));
      }

      await Future.wait(pingTasks);
    }

    setState(() {
      isScanning = false;
    });
  }

  Future<void> _scanLinuxDevice(String ip) async {
    try {
      final result = await _checkSSHPort(ip);
      if (result) {
        String deviceName = await _getDeviceNameFromSSH(ip);
        setState(() {
          if (!devices.any((device) => device['ip'] == ip)) {
            devices.add({'ip': ip, 'name': deviceName});
          }
        });
      }
    } catch (e) {
      print('Error scanning device $ip: $e');
    }
  }

  Future<bool> _checkSSHPort(String ip) async {
    try {
      final socket = await Socket.connect(ip, 22, timeout: Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String> _getDeviceNameFromSSH(String ip) async {
    try {
      final result = await Process.run('ssh', ['-o', 'StrictHostKeyChecking=no', 'aytac@$ip', 'hostname']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      print('Error getting device hostname via SSH: $e');
    }
    return '';
  }

  void _selectIp(String ip) {
    setState(() {
      selectedIp = ip;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('IP Scanner'),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: isScanning ? null : scanNetwork,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(isScanning ? 'Scanning...' : 'Scan the Devices'),
            ),
            if (subnetAddress != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("Subnet IP Address: $subnetAddress"),
              ),
            if (isScanning) CircularProgressIndicator(),
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    title: Text(device['ip']!),
                    subtitle: Text(device['name']!),
                    onTap: () => _selectIp(device['ip']!),
                    tileColor: selectedIp == device['ip'] ? Colors.red[100] : null,
                  );
                },
              ),
            ),
            if (selectedIp.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => WifiConnectionScreen()),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Selected IP: $selectedIp')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.redAccent,
                  ),
                  child: Text(
                    'Continue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}





class WifiConnectionScreen extends StatefulWidget {
  @override
  _WifiConnectionScreenState createState() => _WifiConnectionScreenState();
}

class _WifiConnectionScreenState extends State<WifiConnectionScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool isContinueButtonVisible = false;  // Continue butonunun görünürlüğünü kontrol eden değişken

  Future<void> connectWifi() async {
    String ssid = _ssidController.text;
    String password = _passwordController.text;

    try {
      final response = await http.post(
        Uri.parse('http://$selectedIp:5000/connect_wifi'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'ssid': ssid, 'password': password}),
      );

      setState(() {
        isContinueButtonVisible = false;  
      });

       
    } catch (e) {
      setState(() {
        isContinueButtonVisible = true;  
      });

     
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Wi-Fi Connection'),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        automaticallyImplyLeading: false
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter Wi-Fi Details:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Name (SSID)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Password',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: connectWifi,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(
                'Connect',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => ApiKeyScreen()),  
                  );
                },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(
                'Skip',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 10),
            Visibility(
              visible: isContinueButtonVisible,  
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => IPScanner()),  
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: Colors.redAccent,
                ),
                child: Text(
                  'Continue',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
            
          ],
        ),
      ),
    );
  }
}


class ApiKeyScreen extends StatefulWidget {
  
  @override
  _ApiKeyScreenState createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final TextEditingController _controller = TextEditingController();

  Future<void> _submitApiKey() async {
    final response = await http.post(
      Uri.parse('http://$selectedIp:5000/save_api_key'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'api_key': _controller.text}),
    );

    if (response.statusCode == 200) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomePage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit API Key: ${response.statusCode}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Enter API Key'),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        automaticallyImplyLeading: false
      ),
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter your API key below:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'API Key',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitApiKey,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(
                'Submit API Key',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => HomePage()),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(
                'Skip',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {


  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  String _response = '';
  late stt.SpeechToText _speechToText;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _speechToText = stt.SpeechToText();
  }

  Future<void> _startListening() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) => print('Status: $status'),
      onError: (error) => print('Error: $error'),
    );
    if (available) {
      setState(() => _isListening = true);
      _speechToText.listen(onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords; // Speech-to-text
        });
      });
    } else {
      print('Speech recognition not available');
    }
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  Future<void> _sendText() async {
    final response = await http.post(
      Uri.parse('http://$selectedIp:5000/process'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'text': _controller.text}),
    );

    if (response.statusCode == 200) {
      setState(() {
        _response = json.decode(response.body)['result'];
      });
    } else {
      setState(() {
        _response = 'Error: ${response.statusCode}';
      });
    }
  }
  Future<void> _exitApp() async {
    try {
      final response = await http.post(
        Uri.parse('http://$selectedIp:5000/shutdown'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _response = 'Exit command executed successfully';
        });
      } else {
        setState(() {
          _response = 'Failed to execute exit command';
        });
      }
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
    }
  }
   @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Robot Control'),
        centerTitle: true,
        backgroundColor: Colors.redAccent,
        automaticallyImplyLeading: false, // Disables the back button
      ),
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter a command or use speech-to-text:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Command',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _sendText,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(
                'Send Command',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isListening ? _stopListening : _startListening,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.green,
              ),
              child: Text(
                _isListening ? 'Stop Listening' : 'Start Listening',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Response: $_response',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.redAccent),
            ),
            SizedBox(height: 20),
            Visibility(visible: false,
            child:ElevatedButton(
              onPressed: _exitApp,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 15),
                backgroundColor: Colors.redAccent,
              ),
              child: Text(
                'Exit',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),),
          ],
        ),
      ),
    );
  }
}