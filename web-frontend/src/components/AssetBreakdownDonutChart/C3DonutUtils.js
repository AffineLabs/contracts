import c3 from "c3";

let C3DonutUtils = (params) => {
  return c3.generate({
    data: {
      bindto: params.bindto,
      columns: params.data,
      type: "donut",
    },
    donut: {
      title: params.title,
      expand: true,
    },
    legend: {
      position: "right",
    },
  });
};

export default C3DonutUtils;
