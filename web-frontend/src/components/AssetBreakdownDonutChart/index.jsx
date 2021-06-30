import React, { Component } from "react";
import C3DonutUtils from "./C3DonutUtils";

import * as d3 from "d3";

class AssetBreakdownDonutChart extends Component {
  state = {
    // TODO: REMOVE
    data: [
      ["HYLD", 120],
      ["LYLD", 100],
      ["MYLD", 100],
      ["SPY", 30],
      ["VGT", 50],
      ["BTC-ETH", 80],
      ["ALTC1", 140],
      ["ALTC2", 140],
    ],
  };

  componentDidMount() {
    this.chart = C3DonutUtils({
      bindto: "#chart",
      data: this.state.data,
      title: "High Risk",
    });
  }

  componentDidUpdate() {
    this.chart.load({ unload: true, columns: this.state.data });
    d3.select("#chart .c3-chart-arcs-title").node().innerHTML =
      this.state.title;
  }

  updateData = () => {
    this.setState({
      data: [
        ["HYLD", 90],
        ["LYLD", 80],
        ["MYLD", 90],
        ["SPY", 50],
        ["VGT", 40],
        ["BTC-ETH", 100],
        ["ALTC", 100],
      ],
      title: "Medium Risk",
    });
  };

  render() {
    return (
      <div>
        <div id="chart"></div>
        <button className="btn btn-primary m-2" onClick={this.updateData}>
          Update Graph
        </button>
      </div>
    );
  }
}

export default AssetBreakdownDonutChart;
