// bindto: d3.select("#portfolioDonut"),
const data = [
  { "Multiplyr Portfolio": 100, "US Bonds": 100 },
  { "Multiplyr Portfolio": 108, "US Bonds": 101 },
  { "Multiplyr Portfolio": 119, "US Bonds": 102 },
  { "Multiplyr Portfolio": 127, "US Bonds": 103 },
  { "Multiplyr Portfolio": 136, "US Bonds": 104 },
  { "Multiplyr Portfolio": 150, "US Bonds": 105 },
  { "Multiplyr Portfolio": 166, "US Bonds": 106 },
  { "Multiplyr Portfolio": 177, "US Bonds": 107 },
  { "Multiplyr Portfolio": 195, "US Bonds": 108 },
  { "Multiplyr Portfolio": 211, "US Bonds": 109 },
  { "Multiplyr Portfolio": 234, "US Bonds": 110 },
  { "Multiplyr Portfolio": 249, "US Bonds": 111 },
  { "Multiplyr Portfolio": 272, "US Bonds": 112 },
  { "Multiplyr Portfolio": 299, "US Bonds": 113 },
  { "Multiplyr Portfolio": 324, "US Bonds": 114 },
  { "Multiplyr Portfolio": 357, "US Bonds": 116 },
  { "Multiplyr Portfolio": 393, "US Bonds": 117 },
  { "Multiplyr Portfolio": 430, "US Bonds": 118 },
  { "Multiplyr Portfolio": 472, "US Bonds": 119 },
  { "Multiplyr Portfolio": 504, "US Bonds": 120 },
  { "Multiplyr Portfolio": 541, "US Bonds": 122 },
  { "Multiplyr Portfolio": 589, "US Bonds": 123 },
  { "Multiplyr Portfolio": 638, "US Bonds": 124 },
  { "Multiplyr Portfolio": 679, "US Bonds": 125 },
  { "Multiplyr Portfolio": 726, "US Bonds": 126 },
  { "Multiplyr Portfolio": 787, "US Bonds": 128 },
  { "Multiplyr Portfolio": 859, "US Bonds": 129 },
  { "Multiplyr Portfolio": 911, "US Bonds": 130 },
  { "Multiplyr Portfolio": 968, "US Bonds": 132 },
  { "Multiplyr Portfolio": 1072, "US Bonds": 133 },
  { "Multiplyr Portfolio": 1190, "US Bonds": 134 },
];

function computeReturnArr(initial = 100, monhtly = 0) {
  function multiplySingleObj(obj) {
    newObj = {};
    for (const [key, value] of Object.entries(obj)) {
      newObj[key] = (value * initial) / 100.0;
    }
    return newObj;
  }
  return data.map((obj) => multiplySingleObj(obj));
}

var portfolioDonut = c3.generate({
  data: {
    bindto: document.getElementById("portfolioDonut"),
    columns: [
      ["HYLD", 120],
      ["LYLD", 100],
      ["MYLD", 100],
      ["SPY", 30],
      ["VGT", 50],
      ["BTC-ETH", 80],
      ["ALTC", 50],
    ],
    type: "donut",
  },
  donut: {
    title: "Risk: High",
    expand: true,
  },
  legend: {
    position: "right",
  },
});
// //

function projected_portfolio_string(val, principal = 100) {
  return (
    "$" +
    val.toLocaleString() +
    " (+" +
    ((val / principal - 1) * 100).toFixed(1).toString() +
    "%)"
  );
}

var chart = c3.generate({
  data: {
    bindto: "#lineChart",
    onmouseover: function (x) {
      const sel = document.getElementById("projected-return");
      sel.innerHTML = projected_portfolio_string(
        data[x.x]["Multiplyr Portfolio"]
      );
    },
    onmouseout: function () {
      const sel = document.getElementById("projected-return");
      sel.innerHTML = projected_portfolio_string(
        data[30]["Multiplyr Portfolio"]
      );
    },
    json: data,
    keys: {
      value: ["Multiplyr Portfolio", "US Bonds"],
    },
    // type: "area-spline",
    types: { "Multiplyr Portfolio": "area-spline", data1: "spline" },
    hide: ["US Bonds"],
  },
  axis: {
    y: {
      show: true,
      tick: {
        values: [100, 500, 1000, 10000, 100000, 1000000],
      },
    },
  },
  grid: {
    x: {
      lines: [{ value: 10, text: "10 Yrs" }],
    },
  },
  spline: {
    interpolation: {
      type: "monotone",
    },
  },
  tooltip: {
    horizontal: true,
    format: {
      value: function (value, ratio, id, index) {
        return value;
      },
    },
  },
  legend: {
    position: "right",
  },
  point: {
    show: false,
  },
});

document.getElementById("portfolioDonut").appendChild(portfolioDonut.element);
document.getElementById("lineChart").appendChild(chart.element);

let yearlyInvest = document.getElementById("yearly-invest");
yearlyInvest.oninput = handleInput;

function handleInput(e) {
  chart.load({
    json: computeReturnArr(e.target.value),
    keys: {
      value: ["Multiplyr Portfolio", "US Bonds"],
    },
  });
  console.log(e.target.value);
  console.log(computeReturnArr(e.target.value));
}
//
const sel = document.getElementById("projected-return");
sel.innerHTML = projected_portfolio_string(data[30]["Multiplyr Portfolio"]);

$(document).ready(function () {
  $("#LYLD-parent").click(function (e) {
    e.preventDefault();
    $(this).toggleClass("clicked-table");
    $(".LYLD").toggle(300);
  });

  $(".LYLD").click(function (e) {
    e.preventDefault();
    console.log(this.id);
  });
});
