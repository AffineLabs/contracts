import React from "react";
import { BrowserRouter as Router, Switch, Route } from "react-router-dom";

import "./App.css";
import PortfolioPage from "./pages/portfolio";

const App = () => {
  let loggedIn = true;

  if (loggedIn) {
    return (
      // ROUTING SHOULD BE HANDLED HERE
      <Router>
        <Switch>
          <Route path="/portfolio">
            <PortfolioPage />
          </Route>
          <Route path="/">
            <PortfolioPage />
          </Route>
        </Switch>
      </Router>
    );
  } else {
    return <div>Please login!</div>;
  }
};

export default App;
