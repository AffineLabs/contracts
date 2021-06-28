import React, { Component } from "react";
import NavBar from "./components/navBar";
import PortfolioTable from "./components/portfolioTable";
import RiskSlider from "./components/riskSlider";

class App extends Component {
  state = {};
  render() {
    return (
      <div className="container-fluid ms-2">
        <React.Fragment>
          <NavBar />
          <div className="row">
            <div className="col-4">
              <RiskSlider />
            </div>
            <div className="col-8">Right</div>
          </div>
          <div className="row">
            <div className="col-4">
              <PortfolioTable />
            </div>
            <div className="col-8">Right</div>
          </div>
        </React.Fragment>
      </div>
    );
  }
}

export default App;
