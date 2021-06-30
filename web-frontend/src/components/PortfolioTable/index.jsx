import React, { Component } from "react";
import PortfolioRow from "../PortfolioRow";

class PortfolioTable extends Component {
  state = { holdings: ["SPY", "Nexo", "Compound"] };

  // clickedRow = (aseet) => {
  //   this.props.updateView(asset);
  // };

  render() {
    return (
      <div>
        This is a portfolio table
        <table width="100%">
          <thead>
            <tr>
              <th>Asset</th>
              <th>APY</th>
              <th>Percentage</th>
            </tr>
          </thead>
          <tbody>
            {this.state.holdings.map((x) => (
              <PortfolioRow
                updateView={this.props.updateView}
                key={x}
                asset={x}
              />
            ))}
          </tbody>
        </table>
        <button className="btn btn-primary btn-lg">Click!</button>
      </div>
    );
  }
}

export default PortfolioTable;
