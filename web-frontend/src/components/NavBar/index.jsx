import React, { Component } from "react";
// Source: https://material-ui.com/components/material-icons/

import {
  Explore,
  AccountCircle,
  DonutLarge,
  TrendingUp,
  Face,
  AccountBalanceWallet,
  AccountBalance,
  SyncAlt,
  PanoramaSharp,
} from "@material-ui/icons";
import "./NavBar.css";
import { xml } from "d3";

const DropdownItem = (props) => {
  const CustomIcon = props.params.icon;
  console.log(props.params);
  // console.log(params.label);

  return (
    <li>
      <a className="dropdown-item" href={props.params.url}>
        <CustomIcon className="material-icons" /> {props.params.label}
      </a>
    </li>
  );
};

const MenuItem = (props) => {
  const params = props.params;
  const CustomIcon = params.icon;
  if ("submenu" in params) {
    return (
      <li className="nav-item dropdown">
        <a
          className="nav-link dropdown-toggle"
          href="#account"
          id="navbarDropdown"
          role="button"
          data-bs-toggle="dropdown"
          aria-expanded="false"
        >
          <CustomIcon className="material-icons" /> {params.label}
        </a>
        <ul
          className="dropdown-menu dropdown-menu-end"
          aria-labelledby="navbarDropdown"
        >
          {params.submenu.map((x) => (
            <DropdownItem key={x.label} params={x} />
          ))}
        </ul>
      </li>
    );
  } else {
    return (
      <li className="nav-item">
        <a className="nav-link" href={params.url}>
          <CustomIcon className="material-icons" /> {params.label}
        </a>
      </li>
    );
  }
};

// TODO: What happens if multiple dropdown list menu exist?
const menuHierarchy = [
  { url: "./", icon: DonutLarge, label: "Portfolio" },
  { url: "./explore", icon: Explore, label: "Explore" },
  { url: "./optimize", icon: TrendingUp, label: "Optimize" },
  {
    url: "#account",
    icon: AccountCircle,
    label: "Account",
    submenu: [
      {
        url: "./wallet",
        icon: AccountBalanceWallet,
        label: "Wallet",
      },
      {
        url: "./transactions",
        icon: SyncAlt,
        label: "Transactions",
      },
      {
        url: "./banking",
        icon: AccountBalance,
        label: "Banking",
      },
      {
        url: "./profile",
        icon: Face,
        label: "Profile & KYC",
      },
    ],
  },
];
class NavBar extends Component {
  state = {};
  render() {
    // TODO: Think of a sane refactor
    return (
      <nav className="navbar navbar-expand-lg navbar-light" id="main-nav">
        <a className="navbar-brand" href="./">
          <img
            src="./m.svg"
            width="30"
            height="27"
            className="material-icons p-1"
            alt=""
          />
          Multiplyr.Ai
        </a>

        <button
          className="navbar-toggler"
          type="button"
          data-toggle="collapse"
          data-target="#navbarNavDropdown"
          aria-controls="navbarNavDropdown"
          aria-expanded="false"
          aria-label="Toggle navigation"
        >
          <span className="navbar-toggler-icon"></span>
        </button>

        <div
          className="collapse navbar-collapse flex-grow-1"
          id="navbarNavDropdown"
        >
          <ul className="navbar-nav ms-auto flex-nowrap me-2">
            {menuHierarchy.map((x) => (
              <MenuItem params={x} />
            ))}
          </ul>
        </div>
      </nav>
    );
  }
}

export default NavBar;
