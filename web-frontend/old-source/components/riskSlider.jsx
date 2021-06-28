import React, { Component } from "react";

class RiskSlider extends Component {
  state = {
    riskLevels: ["Low", "Medium-Low", "Medium", "Medium-High", "High"],
  };

  render() {
    return (
      <div class="form-floating">
        <select class="form-select pb-0" id="floatingSelect">
          {this.state.riskLevels.map((v, k) => (
            <option key={k} value={k}>
              {v} Risk
            </option>
          ))}
        </select>
        <label for="floatingSelect">Your Desired Risk Level</label>
      </div>
    );
  }
}

export default RiskSlider;
