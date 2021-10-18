from flask import Flask, request, jsonify

from adapter import Adapter

app = Flask(__name__)


@app.before_request
def log_request_info():
    app.logger.debug("Headers: %s", request.headers)
    app.logger.debug("Body: %s", request.get_data())
    app.logger.debug("Params: %s", print(request.form))


@app.after_request
def after(response):
    # todo with response
    print("RESPONSE DEBUG INFO: ", response)
    print("STATUS: ", response.status)
    print("HEADERS: ", response.headers)
    print("DATA: ", response.get_data())
    return response


@app.route("/", methods=["POST"])
def call_adapter():
    data = request.get_json()
    if data == "":
        data = {}
    adapter = Adapter(data)
    print("adapter.result: ", adapter.result)
    return jsonify(adapter.result)


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port="8080", threaded=True)
