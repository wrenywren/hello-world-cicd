from flask import Flask

app = Flask(__name__)


@app.route("/", methods=["GET"])
def hello():
    return "Hello World\n", 200


@app.route("/health", methods=["GET"])
def health():
    return "OK\n", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
