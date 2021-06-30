import React, { Component } from "react";

function generate_row(params) {
  return (
    <tr className="blah">
      <td>{params.asset}</td>
      <td>{params.apy}%</td>
      <td>{params.perc}%</td>
    </tr>
  );
}
class PortfolioRow extends Component {
  state = { asset: "Nexo", apy: 8.6, perc: 11.2 };

  //   constructor(props) {
  //     super(props);
  //     // console.log("consturction", this.props);
  //   }
  render() {
    let top_row = generate_row({ ...this.state, asset: this.props.asset });
    const params = this.state;

    if (true) {
      return (
        <tr
          onClick={() => this.props.updateView(this.props.asset)}
          className="blah"
        >
          <td>{this.props.asset}</td>
          <td>{params.apy}%</td>
          <td>{params.perc}%</td>
        </tr>
      );
    } else {
      return [top_row, top_row];
    }
  }
}

export default PortfolioRow;
