CREATE TABLE IF NOT EXISTS sales (
    order_id INT PRIMARY KEY,
    order_date DATE NOT NULL,
    category VARCHAR(80) NOT NULL,
    product VARCHAR(120) NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(12, 2) NOT NULL
);

INSERT INTO sales (order_id, order_date, category, product, quantity, unit_price)
VALUES
(1, '2026-01-05', 'Electronics', 'Laptop', 2, 55000.00),
(2, '2026-01-10', 'Furniture', 'Chair', 5, 3500.00),
(3, '2026-02-02', 'Electronics', 'Mobile', 3, 20000.00),
(4, '2026-02-12', 'Clothing', 'Shirt', 10, 1200.00),
(5, '2026-03-08', 'Furniture', 'Table', 2, 8500.00);
