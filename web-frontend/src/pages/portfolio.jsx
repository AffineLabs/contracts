import React from "react";
import NavBar from "features/navBar";

const PortfolioPage = () => {
  return (
    <div className="container-fluid m-2">
      <NavBar />
      <div className="row">
        <div className="col-sm-4">
          Lorem ipsum dolor sit amet consectetur adipisicing elit.
        </div>
        <div className="col-sm-8">
          Lorem ipsum dolor sit amet consectetur adipisicing elit.
        </div>
      </div>

      <div className="row">
        <div className="col-sm-4 portfolio-box">
          Lorem ipsum dolor sit amet consectetur adipisicing elit.
        </div>
        <div className="col-sm-8 ">
          Lorem ipsum dolor sit amet consectetur adipisicing elit.
        </div>
      </div>
    </div>
  );
};

export default PortfolioPage;
