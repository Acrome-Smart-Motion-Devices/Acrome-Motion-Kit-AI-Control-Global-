from flask import Flask, request, jsonify
from flask_cors import CORS
from groq import Groq
import requests
import json
import time
import math
from smd.red import Master,Red,OperationMode
from serial.tools.list_ports import comports
from platform import system
import os
import subprocess
import sys
import signal
import logging

# Configure logging
logging.basicConfig(
    filename="app.log",  # File where logs will be saved
    level=logging.DEBUG,  # Capture all levels of logs, including errors
    format="%(asctime)s - %(levelname)s - %(message)s"
)

APIKEY = None
API_KEY_FILE = "api_key.txt"
def USB_Port():
    ports = list(comports())
    usb_names = {
        "Windows": ["USB Serial Port"],
        "Linux": ["/dev/ttyUSB"],
        "Darwin": ["/dev/tty.usbserial", "/dev/tty.usbmodem"]
    }
    os_name = system()
    for port, desc, hwid in sorted(ports):
        if any(name in port or name in desc for name in usb_names.get(os_name, [])):
            return port
    return None
def get_groq_client():
    if not APIKEY:
        raise ValueError("API Key is missing!")
    return Groq(api_key=APIKEY)
def save_api_key(api_key):
    global APIKEY
    APIKEY = api_key
    with open(API_KEY_FILE, "w") as file:
        file.write(api_key)
def load_api_key():
    global APIKEY
    if os.path.exists(API_KEY_FILE):
        with open(API_KEY_FILE, "r") as file:
            APIKEY = file.read().strip()
def connect_wifi(ssid, password):
    try:
        print(f"Connecting to Wi-Fi SSID: {ssid}")
        subprocess.run("sudo nmcli device wifi list",shell=True,check=True)
        command = f"sudo nmcli device wifi connect \"{ssid}\" password {password}"
        subprocess.run(command, shell=True, check=True)
        
        return True
    except subprocess.CalledProcessError as e:
        print(f"Hata: {e}")
        return False



# Function to generate AI response for robot commands
function_instructions = """
You are a robot control assistant. For each question, you should return a JSON object in the following format:
[
    {
        "function": "function_name",
        "parameters": {
            "parameter1": value1,
            "parameter2": value2
        }
    }
]

Available functions:
1. init_robot - Initializes the robot's position. No parameters.
2. linear_movement - Moves the robot a specified distance in cm. If user dont write speed you should use default value. (default value is:30)\n
    - Parameters: cm (int) - Distance to move in cm, speed (int)\n
3. turn_left - Turns the robot a specified degree counterclockwise (left). If the user doesn't write speed, you should use the default value (default value is: 30).\n
    - Parameters: degree (int) - Degree to turn, rotation_speed (int)\n
4. turn_right - Turns the robot a specified degree clockwise (right). If the user doesn't write speed, you should use the default value (default value is: 30).\n
    - Parameters: degree (int) - Degree to turn, rotation_speed (int)\n
5. radial_movement - Moves the robot along a circular path with a given radius and angle.\n
    - Parameters: radius (int), degree (int)\n
NOTE: The first function have to be `init_robot`. Other functions will come after init_robot function.\n
NOTE: Understand the prompt given by the user\n

"""

def get_groq_response(prompt):
    client = Groq(api_key=APIKEY)
    response = client.chat.completions.create(
        model="llama-3.3-70b-versatile",
        messages=[{"role": "user", "content": prompt}, {"role": "system", "content": function_instructions}]
    )
    try:
        content = response.choices[0].message.content
        
        
        return json.loads(content)  # Parse JSON response
    except Exception as e:
        return None

# Robot Controller Implementation
class RobotController:
    def __init__(self, wheel_radius, robot_width):
        self.m = None
        self.x = None
        self.y = None
        self.angle = None
        self.wheel_radius = wheel_radius
        self.robot_width = robot_width
        self.robot_initialized = False  

    def init_robot(self):
        if self.robot_initialized:
            return self.x, self.y, self.angle  

        self.m = Master(USB_Port())
        self.x = 0
        self.y = 0
        self.angle = 0
        self.m.attach(Red(0))
        self.m.attach(Red(1))
        self.m.set_operation_mode(0, OperationMode.Velocity)
        self.m.set_operation_mode(1, OperationMode.Velocity)
        self.m.set_shaft_rpm(0,100)
        self.m.set_shaft_rpm(1,100)
        self.m.set_shaft_cpr(0,6533)
        self.m.set_shaft_cpr(1,6533)
        self.m.enable_torque(0, True)
        self.m.enable_torque(1, True)
        self.m.set_control_parameters_velocity(0, 25.83, 4.27, 0)
        self.m.set_control_parameters_velocity(1, 29.48, 5.50, 0)
        self.robot_initialized = True  

        return self.x, self.y, self.angle

    def linear_movement(self, cm, speed=30):
      kp = 1
      if speed > 100:
          print("You cannot exceed speed 100.")
          speed = 30
      print(speed)
  
  
      try:
          motor1_offset = self.m.get_position(0) / 6533
          motor2_offset = self.m.get_position(1) / 6533
          err = 100
  
          while abs(err) > 2:
              try:
                  # Motor pozisyonlarını oku
                  motor1 = self.m.get_position(0) / 6533 - motor1_offset
                  motor2 = self.m.get_position(1) / 6533 - motor2_offset
                  motor_mean = (-motor1 + motor2) / 2
  
                  # Robotun ilerlediği mesafeyi hesapla
                  car_pos = motor_mean * 2 * math.pi * self.wheel_radius
                  err = cm - car_pos
                  print(cm, car_pos)
  
                  # PID tabanlı hız kontrolü
                  calc_velo = err * kp
                  if calc_velo > speed:
                      calc_velo = speed
                  elif calc_velo < -speed:
                      calc_velo = -speed
  
                  # Motor hızlarını ayarla
                  self.m.set_velocity(0, -calc_velo)
                  self.m.set_velocity(1, calc_velo)
  
              except Exception as e:
                  print("Error during motor position read or calculation:", str(e))
                  continue  
  
      except Exception as e:
          print("Error initializing motor positions:", str(e))
  
      
      self.m.set_velocity(0, 0)
      self.m.set_velocity(1, 0)
  
      # Robotun pozisyonunu güncelle
      self.x += cm
      return self.x, self.y, self.angle



    def turn_left(self, degree, rotation_speed=30):
        """Robotun saat yönünün tersine (sola) dönüşü pozisyon tabanlı kontrol ile."""
        rotation_speed = float(rotation_speed)
        degree = float(degree)

        if rotation_speed > 100:
            print("Rotation speed cannot exceed 100.")
            rotation_speed = 30
        if rotation_speed < -100:
            print("Rotation speed cannot be less than -100.")
            rotation_speed = -30

        print("Adjusted rotation speed:", rotation_speed)

        # Dönüş sırasında gereken tekerlek mesafesi
        arc_length = (degree / 360) * (math.pi * self.robot_width)  # Robotun döneceği yay uzunluğu
        wheel_rotation = arc_length / (2 * math.pi * self.wheel_radius)  # Tekerleklerin dönmesi gereken tur sayısı

        # Motorların hedef pozisyonlarını hesapla
        left_motor_target = self.m.get_position(0) - (wheel_rotation * 6533)  # Sol motor geri
        right_motor_target = self.m.get_position(1) + (wheel_rotation * 6533)  # Sağ motor ileri

        # Hareketi başlat
        while True:
            left_motor_current = self.m.get_position(0)
            right_motor_current = self.m.get_position(1)

            # Her iki motorun hedef pozisyona ne kadar yaklaştığını kontrol et
            left_error = abs(left_motor_target - left_motor_current)
            right_error = abs(right_motor_target - right_motor_current)
            print(left_error)
            print(right_error)
            if left_error < 525 or right_error < 525:  # Hata toleransı
                self.m.set_velocity(0, 0)
                self.m.set_velocity(1, 0)
                break

            # Motorlara hız gönder
            if left_motor_current > left_motor_target:
                self.m.set_velocity(0, rotation_speed)  # Sol motor geri

            if right_motor_current < right_motor_target:
                self.m.set_velocity(1, rotation_speed)  # Sağ motor ileri
            

        # Robotun açısını güncelle
        self.angle -= degree
        if self.angle < 0:
            self.angle += 360

        print(f"Updated Position: x={self.x}, y={self.y}, angle={self.angle}")
        return self.x, self.y, self.angle


    def turn_right(self, degree, rotation_speed=30):
        """Robotun saat yönünde (sağa) dönüşü pozisyon tabanlı kontrol ile."""
        if rotation_speed > 100:
            print("Rotation speed cannot exceed 100.")
            rotation_speed = 40
        if rotation_speed < -100:
            print("Rotation speed cannot be less than -100.")
            rotation_speed = -40
    
        print("Adjusted rotation speed:", rotation_speed)
    
        # Dönüş sırasında gereken tekerlek mesafesi
        arc_length = (degree / 360) * (math.pi * self.robot_width)  # Robotun döneceği yay uzunluğu
        wheel_rotation = arc_length / (2 * math.pi * self.wheel_radius)  # Tekerleklerin dönmesi gereken tur sayısı
    
        # Motorların hedef pozisyonlarını hesapla
        left_motor_target = self.m.get_position(0) + (wheel_rotation * 6533)  # Sol motor ileri
        right_motor_target = self.m.get_position(1) - (wheel_rotation * 6533)  # Sağ motor geri
    
        # Hareketi başlat
        while True:
            left_motor_current = self.m.get_position(0)
            right_motor_current = self.m.get_position(1)
    
            # Her iki motorun hedef pozisyona ne kadar yaklaştığını kontrol et
            left_error = abs(left_motor_target - left_motor_current)
            right_error = abs(right_motor_target - right_motor_current)
            print(left_error)
            print(right_error)
            if left_error < 525 or right_error < 525:  # Hata toleransı
                self.m.set_velocity(0, 0)
                self.m.set_velocity(1, 0)
                break
    
            # Motorlara hız gönder
            if left_motor_current < left_motor_target:
                self.m.set_velocity(0, -rotation_speed)  # Sol motor ileri
            
    
            if right_motor_current > right_motor_target:
                self.m.set_velocity(1, -rotation_speed)  # Sağ motor geri
    
        # Robotun açısını güncelle
        self.angle += degree
        if self.angle >= 360:
            self.angle -= 360
    
        print(f"Updated Position: x={self.x}, y={self.y}, angle={self.angle}")
        return self.x, self.y, self.angle






    def radial_movement(self, radius, degree, speed=40, steps=20):
        """
        Robotun belirtilen yarıçap (radius) ve açı (degree) boyunca bir daire üzerinde hareket etmesini sağlar.

        Args:
            radius (float): Dairenin yarıçapı (cm). Pozitif değer sağa, negatif değer sola döner.
            degree (float): Hareket edilecek toplam açı (derece).
            speed (int): Maksimum hız (% olarak, -100 ile 100 arası).
            steps (int): Hareketi kaç adıma böleceğinizi belirtir.
        """
        if speed > 100:
            speed = 100
        if speed < -100:
            speed = -100

        speed=40
        
        
        degree_per_step = degree / steps
        arc_length_per_step = (2 * math.pi * abs(radius) * abs(degree_per_step)) / 360

        for _ in range(steps):
           
            if radius > 0:  
                inner_wheel_speed = speed * (radius - (self.robot_width / 2)) / radius
                outer_wheel_speed = speed
            else:  
                inner_wheel_speed = speed
                outer_wheel_speed = speed * (radius + (self.robot_width/ 2)) / radius

            
            self.m.set_velocity(0, inner_wheel_speed)  
            self.m.set_velocity(1, outer_wheel_speed)  

            
            time_per_step = arc_length_per_step / (speed * (2 * math.pi * (abs(radius)) / 60))  
            
            # Bekle
            time.sleep(time_per_step)

        
        self.m.set_velocity(0, 0)
        self.m.set_velocity(1, 0)

        
        self.angle += degree
        self.angle %= 360  

        return self.x, self.y, self.angle

robot_controller = RobotController(wheel_radius=3.75, robot_width=28)

# Flask App Setup
app = Flask(__name__)
CORS(app)
@app.route('/connect_wifi', methods=['POST'])
def connect_wifi_route():
    data = request.get_json()
    ssid = data.get('ssid')
    password = data.get('password')

    if ssid and password:
        if connect_wifi(ssid, password):
            return jsonify({'status': 'success', 'message': 'Wi-Fi bağlantısı başarılı.'}), 200
        else:
            return jsonify({'status': 'error', 'message': 'Wi-Fi bağlantısı başarısız.'}), 500
    else:
        return jsonify({'status': 'error', 'message': 'SSID veya şifre eksik.'}), 400
load_api_key()
@app.route('/save_api_key', methods=['POST'])
def save_api_key_endpoint():
    data = request.get_json()
    if not data or "api_key" not in data:
        return jsonify({"error": "No API key provided"}), 400

    api_key = data["api_key"]
    save_api_key(api_key)
    return jsonify({"message": "API key saved successfully"}), 200
@app.route('/shutdown', methods=['POST'])
def shutdown():
    try:
        os.kill(os.getpid(), signal.SIGINT)  # Flask'ı düzgün şekilde kapatır
        return jsonify(message='Shutting down...'), 200
    except Exception as e:
        # Hata durumunda 500 ile geri dönüyoruz, ancak Flutter'a Error mesajı dönmeyecek.
        return jsonify(message='Error occurred while shutting down the server', error=str(e)), 500  # Flask'ın genellikle CTRL+C ile kapatılmasını sağlar.
@app.route('/process', methods=['POST'])
def process_text():
    data = request.get_json()
    if not data or "text" not in data:
        return jsonify({"error": "No text provided"}), 400

    user_text = data["text"]
    try:
        
        ai_response = get_groq_response(user_text)
        print(ai_response)
        if not ai_response:
            return jsonify({"error": "AI response generation failed"}), 500

        success = execute_function(ai_response)
        if success:
            return jsonify({"result": "Robot executed the commands successfully!"}), 200
        else:
           return jsonify({"error": "Error occurred while executing commands."}), 500

    except Exception as e:
        logging.exception(f"Unexpected error while processing text: {str(e)}")
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500

def execute_function(response):
    for func_call in response:
        function = func_call.get("function")
        parameters = func_call.get("parameters", {})

        try:
            print(f"Executing function: {function} with parameters: {parameters}")

            if function == "init_robot":
                robot_controller.init_robot()
            elif function == "linear_movement":
                robot_controller.linear_movement(parameters.get("cm", 0), parameters.get("speed", 30))
            elif function == "turn_left":
                robot_controller.turn_left(parameters.get("degree", 0), parameters.get("rotation_speed", 20))
            elif function =="turn_right":
                robot_controller.turn_right(parameters.get("degree", 0), parameters.get("rotation_speed", 20))
            elif function == "radial_movement":
                robot_controller.radial_movement(parameters.get("radius", 0), parameters.get("degree", 0))
            elif function=="stop":
                robot_controller.stop()
            else:
                raise ValueError(f"Unknown function: {function}")

        except Exception as e:
            print(f"Error while executing {function}: {e}")
            return False  # Hata oluştuysa `False` döndür

    return True  # Tüm fonksiyonlar başarılı şekilde çalıştıysa `True` döndür


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
