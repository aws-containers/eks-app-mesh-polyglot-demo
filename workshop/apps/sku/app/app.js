//Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//SPDX-License-Identifier: MIT-0

const express = require("express");
const app = express();


app.set('view engine', 'ejs')

app.get("/sku", (req, res) => {
  console.log("SKU Detail Get Request Successful");
res.render('index.ejs', {skus: [{"id": "SKU-BK-2502967", "name": "Road Bike SKU"},{"id": "SKU-BK-2502968", "name": "Mountain Bike SKU"}, {"id": "SKU-BK-2502969", "name": "Dirt Bike SKU"}, {"id": "SKU-BK-2502970", "name": "Racer Bike SKU"}, {"id": "SKU-BK-250271", "name": "Premuim Bike SKU"}, {"id": "SKU-BK-2502972", "name": "Custom Bike SKU"}]})

}
);



app.get("/ping", (req, res, next) => {
  res.json("Healthy")
});


app.listen(3000, () => {
 console.log("Server running on port 3000");
});