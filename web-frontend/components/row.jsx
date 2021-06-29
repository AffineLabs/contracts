import React, { Component } from "react";

class Row extends Component {
  state = {
    assetName: this.props.assetName,
    assetPrice: this.props.assetPrice,
    assetDesc: this.props.assetDesc,
  };
  render() {
    return (
      <tr
        onClick={() => {
          console.log("You clicked " + this.state.assetName);
        }}
      >
        <td>{this.state.assetName}</td>
        <td>{this.state.assetPrice}</td>
        <td>{this.state.assetDesc}</td>
      </tr>
    );
  }
}

export default Row;
