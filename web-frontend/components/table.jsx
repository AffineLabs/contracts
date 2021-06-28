import React, { Component } from "react";
import Row from "./row";

class Table extends Component {
  state = {};
  render() {
    return (
      <div>
        <table className="table table-bordered table-condensed table-striped table-hover">
          <thead>
            <tr>
              <th>Ticker</th>
              <th>Price</th>
              <th>Desc</th>
            </tr>
          </thead>
          <tbody>
            {<Row assetName="BTC" assetPrice="30000" assetDesc="Bitcoin" />}
            {<Row assetName="ETH" assetPrice="2000" assetDesc="Ethereum" />}
          </tbody>
        </table>
      </div>
    );
  }
}

export default Table;
