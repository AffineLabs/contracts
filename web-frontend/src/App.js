import React, { Component } from "react";
import NavBar from "./components/NavBar";
import PortfolioTable from "./components/PortfolioTable";
import AssetBreakdownDonutChart from "./components/AssetBreakdownDonutChart";
import LineChart from "./components/LineChart";

import "./App.css";
import { SwitchCamera } from "@material-ui/icons";

const lorem =
  "Lorem ipsum dolor sit amet, consectetur adipisicing elit. Non optio illum, temporibus deleniti architecto voluptatum culpa similique magnam sapiente odit doloribus cum ex, suscipit libero, corruptiitaque voluptatem officiis maiores!";

class App extends Component {
  state = {
    assetPortfolio: [{ assetName: "Nexo", apy: 8.6, perc: 11 }],
    watchList: [],
    currentUser: {
      username: "tarikm",
      jwt: "blahblah",
      totalBalance: 11450,
      defaultRiskLevel: 3,
    },
  };
  updateView = (asset) => {
    console.log("VIEW", asset);
  };

  render() {
    return (
      // ROUTING SHOULD BE HANDLED HERE
      <div className="container-fluid m-2">
        <NavBar />
        <div className="row">
          <div className="col-sm-4">
            <AssetBreakdownDonutChart />
          </div>
          <div className="col-sm-8"></div>
        </div>

        <div className="row">
          <div className="col-sm-4 portfolio-box">
            <PortfolioTable updateView={this.updateView} />
          </div>
          <div className="col-sm-8 "> {lorem} </div>
        </div>
      </div>
    );
  }
}

export default App;
