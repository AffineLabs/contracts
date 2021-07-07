import React, { Component } from "react";
import C3LineChartUtils from "./C3LineChartUtils";

class LineChart extends Component {
  componentDidMount() {
    this.chart = C3LineChartUtils({
      bindTo: "#lineChart",
    });
  }

  componentDidUpdate() {
    // this.chart.load({ unload: true, columns: this.state.data });
    // d3.select("#chart .c3-chart-arcs-title").node().innerHTML =
    //   this.state.title;
  }

  render() {
    return <div id="lineChart"></div>;
  }
}

export default LineChart;
