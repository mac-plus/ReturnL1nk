const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static('public'));

const dataDir = path.join(__dirname, 'data');
const dataFile = path.join(dataDir, 'returns.json');
const uploadDir = path.join(__dirname, 'uploads');

fs.mkdirSync(dataDir, { recursive: true });
fs.mkdirSync(uploadDir, { recursive: true });

let returns = [];
if (fs.existsSync(dataFile)) {
  returns = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
}
function saveData() {
  fs.writeFileSync(dataFile, JSON.stringify(returns, null, 2));
}

app.post('/api/create-case', (req, res) => {
  const { customer, orderId } = req.body;
  if (!customer || !orderId) {
    return res.status(400).json({ error: 'customer and orderId required' });
  }
  const id = uuidv4();
  const record = { id, customer, orderId, status: 'Pending', files: {} };
  returns.push(record);
  saveData();
  res.json({ link: `/return/${id}` });
});

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(uploadDir, req.params.id);
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    cb(null, file.fieldname + path.extname(file.originalname));
  },
});
const upload = multer({ storage });

app.post('/api/upload/:id',
  upload.fields([
    { name: 'productPhoto', maxCount: 1 },
    { name: 'packagePhoto', maxCount: 1 },
    { name: 'labelPhoto', maxCount: 1 },
    { name: 'video', maxCount: 1 },
  ]),
  (req, res) => {
    const record = returns.find(r => r.id === req.params.id);
    if (!record) return res.status(404).send('Invalid ID');

    record.files.productPhoto = req.files.productPhoto ? req.files.productPhoto[0].filename : null;
    record.files.packagePhoto = req.files.packagePhoto ? req.files.packagePhoto[0].filename : null;
    record.files.labelPhoto = req.files.labelPhoto ? req.files.labelPhoto[0].filename : null;
    record.files.video = req.files.video ? req.files.video[0].filename : null;
    record.confirmOriginal = req.body.confirmOriginal === 'on';
    record.status = 'Submitted';
    saveData();
    res.send('Return submitted');
  }
);

app.get('/api/returns', (req, res) => {
  res.json(returns);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
