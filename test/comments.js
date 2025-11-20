const { expect } = require("chai");

describe("Comments", () => {
  it("Testing comments", () => {
    let test = jspreadsheet(root, {
      data: [
        ["", "", ""],
        ["", "", ""],
        ["", "", ""],
      ],
      minDimensions: [3, 3]
    });

    test.setComments("A3", "New comment");

    expect(test.getComments("A3")).to.eql("New comment");
  });
});
