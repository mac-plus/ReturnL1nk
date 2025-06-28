# ReturnL1nk

ReturnL1nk is a prototype application that helps online sellers verify return
packages before issuing refunds. Customers upload photos and an optional video
to confirm product condition. Sellers can view all return cases from a simple
dashboard.

## Features

- Generate unique links for each return request
- Customers upload three required photos and an optional video
- Confirmation checkbox that the returned item is original
- Seller dashboard lists all return cases

## Running the App

```
npm install
node server.js
```

The server listens on `http://localhost:3000`. Open `/dashboard.html` to see all
returns. Share `/return/<id>` links with customers to collect evidence.
