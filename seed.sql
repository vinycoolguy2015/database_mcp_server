-- Database Assistant MCP - Seed Script
-- Creates an e-commerce + CRM database with 50+ tables and thousands of records

DROP DATABASE IF EXISTS ecommerce;
CREATE DATABASE ecommerce;
\c ecommerce;

CREATE SCHEMA IF NOT EXISTS store;
SET search_path TO store, public;

-- ─── Reference / Lookup Tables ──────────────────────────────────────────────

CREATE TABLE store.countries (
    id SERIAL PRIMARY KEY,
    code CHAR(2) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE store.currencies (
    id SERIAL PRIMARY KEY,
    code CHAR(3) UNIQUE NOT NULL,
    name VARCHAR(50) NOT NULL,
    symbol VARCHAR(5)
);

CREATE TABLE store.departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    permissions JSONB DEFAULT '{}'
);

CREATE TABLE store.categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    parent_id INT REFERENCES store.categories(id),
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE store.tags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    slug VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE store.shipping_carriers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    tracking_url_template VARCHAR(255),
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE store.payment_methods (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    provider VARCHAR(50),
    is_active BOOLEAN DEFAULT true
);

-- ─── Core Business Tables ───────────────────────────────────────────────────

CREATE TABLE store.customers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    is_active BOOLEAN DEFAULT true,
    email_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.customer_addresses (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    address_type VARCHAR(20) DEFAULT 'shipping',
    line1 VARCHAR(255) NOT NULL,
    line2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100),
    postal_code VARCHAR(20),
    country_id INT REFERENCES store.countries(id),
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.customer_preferences (
    id SERIAL PRIMARY KEY,
    customer_id INT UNIQUE NOT NULL REFERENCES store.customers(id),
    newsletter_opt_in BOOLEAN DEFAULT false,
    sms_opt_in BOOLEAN DEFAULT false,
    preferred_currency_id INT REFERENCES store.currencies(id),
    preferred_language VARCHAR(10) DEFAULT 'en',
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.segments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    criteria JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.customer_segments (
    customer_id INT NOT NULL REFERENCES store.customers(id),
    segment_id INT NOT NULL REFERENCES store.segments(id),
    assigned_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (customer_id, segment_id)
);

CREATE TABLE store.suppliers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    contact_email VARCHAR(255),
    contact_phone VARCHAR(20),
    country_id INT REFERENCES store.countries(id),
    rating DECIMAL(3,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.warehouses (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address VARCHAR(255),
    city VARCHAR(100),
    country_id INT REFERENCES store.countries(id),
    capacity INT,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE store.products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category_id INT REFERENCES store.categories(id),
    supplier_id INT REFERENCES store.suppliers(id),
    price DECIMAL(10,2) NOT NULL,
    cost DECIMAL(10,2),
    weight_kg DECIMAL(6,3),
    is_active BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.product_images (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES store.products(id),
    url VARCHAR(500) NOT NULL,
    alt_text VARCHAR(255),
    sort_order INT DEFAULT 0,
    is_primary BOOLEAN DEFAULT false
);

CREATE TABLE store.product_tags (
    product_id INT NOT NULL REFERENCES store.products(id),
    tag_id INT NOT NULL REFERENCES store.tags(id),
    PRIMARY KEY (product_id, tag_id)
);

CREATE TABLE store.product_reviews (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES store.products(id),
    customer_id INT NOT NULL REFERENCES store.customers(id),
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title VARCHAR(200),
    body TEXT,
    is_verified_purchase BOOLEAN DEFAULT false,
    is_approved BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.inventory (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES store.products(id),
    warehouse_id INT NOT NULL REFERENCES store.warehouses(id),
    quantity INT NOT NULL DEFAULT 0,
    reserved_quantity INT NOT NULL DEFAULT 0,
    reorder_point INT DEFAULT 10,
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(product_id, warehouse_id)
);

CREATE TABLE store.supplier_products (
    supplier_id INT NOT NULL REFERENCES store.suppliers(id),
    product_id INT NOT NULL REFERENCES store.products(id),
    supplier_sku VARCHAR(50),
    lead_time_days INT,
    min_order_quantity INT DEFAULT 1,
    PRIMARY KEY (supplier_id, product_id)
);

CREATE TABLE store.price_history (
    id SERIAL PRIMARY KEY,
    product_id INT NOT NULL REFERENCES store.products(id),
    old_price DECIMAL(10,2),
    new_price DECIMAL(10,2) NOT NULL,
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT NOW()
);

-- ─── Orders & Payments ──────────────────────────────────────────────────────

CREATE TABLE store.coupons (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    description VARCHAR(255),
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),
    discount_value DECIMAL(10,2) NOT NULL,
    min_order_amount DECIMAL(10,2) DEFAULT 0,
    max_uses INT,
    used_count INT DEFAULT 0,
    valid_from TIMESTAMP NOT NULL,
    valid_until TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE store.orders (
    id SERIAL PRIMARY KEY,
    order_number VARCHAR(20) UNIQUE NOT NULL,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    shipping_address_id INT REFERENCES store.customer_addresses(id),
    billing_address_id INT REFERENCES store.customer_addresses(id),
    coupon_id INT REFERENCES store.coupons(id),
    subtotal DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) DEFAULT 0,
    shipping_cost DECIMAL(10,2) DEFAULT 0,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    currency_id INT REFERENCES store.currencies(id),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.order_items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES store.orders(id),
    product_id INT NOT NULL REFERENCES store.products(id),
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    discount_amount DECIMAL(10,2) DEFAULT 0
);

CREATE TABLE store.order_status_history (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES store.orders(id),
    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    changed_by VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.payments (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES store.orders(id),
    payment_method_id INT REFERENCES store.payment_methods(id),
    amount DECIMAL(10,2) NOT NULL,
    currency_id INT REFERENCES store.currencies(id),
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    transaction_id VARCHAR(100),
    gateway_response JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.shipping (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES store.orders(id),
    carrier_id INT REFERENCES store.shipping_carriers(id),
    tracking_number VARCHAR(100),
    status VARCHAR(30) DEFAULT 'pending',
    shipped_at TIMESTAMP,
    delivered_at TIMESTAMP,
    estimated_delivery DATE,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.returns (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES store.orders(id),
    customer_id INT NOT NULL REFERENCES store.customers(id),
    reason VARCHAR(255),
    status VARCHAR(30) DEFAULT 'requested',
    refund_amount DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE TABLE store.return_items (
    id SERIAL PRIMARY KEY,
    return_id INT NOT NULL REFERENCES store.returns(id),
    order_item_id INT NOT NULL REFERENCES store.order_items(id),
    quantity INT NOT NULL,
    condition VARCHAR(50)
);

CREATE TABLE store.coupon_usage (
    id SERIAL PRIMARY KEY,
    coupon_id INT NOT NULL REFERENCES store.coupons(id),
    customer_id INT NOT NULL REFERENCES store.customers(id),
    order_id INT NOT NULL REFERENCES store.orders(id),
    used_at TIMESTAMP DEFAULT NOW()
);

-- ─── Cart & Wishlist ────────────────────────────────────────────────────────

CREATE TABLE store.carts (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES store.customers(id),
    session_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.cart_items (
    id SERIAL PRIMARY KEY,
    cart_id INT NOT NULL REFERENCES store.carts(id),
    product_id INT NOT NULL REFERENCES store.products(id),
    quantity INT NOT NULL DEFAULT 1,
    added_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.wishlists (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    name VARCHAR(100) DEFAULT 'My Wishlist',
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.wishlist_items (
    id SERIAL PRIMARY KEY,
    wishlist_id INT NOT NULL REFERENCES store.wishlists(id),
    product_id INT NOT NULL REFERENCES store.products(id),
    added_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(wishlist_id, product_id)
);

-- ─── Employees ──────────────────────────────────────────────────────────────

CREATE TABLE store.employees (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    department_id INT REFERENCES store.departments(id),
    hire_date DATE NOT NULL,
    salary DECIMAL(10,2),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.employee_roles (
    employee_id INT NOT NULL REFERENCES store.employees(id),
    role_id INT NOT NULL REFERENCES store.roles(id),
    assigned_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (employee_id, role_id)
);

-- ─── Marketing & Communications ─────────────────────────────────────────────

CREATE TABLE store.email_campaigns (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    subject VARCHAR(255) NOT NULL,
    body_html TEXT,
    segment_id INT REFERENCES store.segments(id),
    status VARCHAR(30) DEFAULT 'draft',
    scheduled_at TIMESTAMP,
    sent_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.email_sends (
    id SERIAL PRIMARY KEY,
    campaign_id INT NOT NULL REFERENCES store.email_campaigns(id),
    customer_id INT NOT NULL REFERENCES store.customers(id),
    status VARCHAR(30) DEFAULT 'sent',
    opened_at TIMESTAMP,
    clicked_at TIMESTAMP,
    sent_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.notifications (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ─── Support ────────────────────────────────────────────────────────────────

CREATE TABLE store.support_tickets (
    id SERIAL PRIMARY KEY,
    ticket_number VARCHAR(20) UNIQUE NOT NULL,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    assigned_to INT REFERENCES store.employees(id),
    subject VARCHAR(255) NOT NULL,
    priority VARCHAR(20) DEFAULT 'medium',
    status VARCHAR(30) DEFAULT 'open',
    order_id INT REFERENCES store.orders(id),
    created_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP
);

CREATE TABLE store.ticket_comments (
    id SERIAL PRIMARY KEY,
    ticket_id INT NOT NULL REFERENCES store.support_tickets(id),
    author_type VARCHAR(20) NOT NULL CHECK (author_type IN ('customer', 'employee')),
    author_id INT NOT NULL,
    body TEXT NOT NULL,
    is_internal BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.knowledge_base_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    parent_id INT REFERENCES store.knowledge_base_categories(id),
    sort_order INT DEFAULT 0
);

CREATE TABLE store.knowledge_base_articles (
    id SERIAL PRIMARY KEY,
    category_id INT REFERENCES store.knowledge_base_categories(id),
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    body TEXT NOT NULL,
    is_published BOOLEAN DEFAULT false,
    view_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ─── Analytics & Tracking ───────────────────────────────────────────────────

CREATE TABLE store.sessions (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(100) UNIQUE NOT NULL,
    customer_id INT REFERENCES store.customers(id),
    ip_address INET,
    user_agent TEXT,
    started_at TIMESTAMP DEFAULT NOW(),
    ended_at TIMESTAMP
);

CREATE TABLE store.page_views (
    id SERIAL PRIMARY KEY,
    session_id INT REFERENCES store.sessions(id),
    path VARCHAR(500) NOT NULL,
    referrer VARCHAR(500),
    duration_seconds INT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.search_queries (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES store.customers(id),
    query_text VARCHAR(255) NOT NULL,
    results_count INT,
    clicked_product_id INT REFERENCES store.products(id),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.recommendations (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    product_id INT NOT NULL REFERENCES store.products(id),
    score DECIMAL(5,4),
    reason VARCHAR(100),
    is_clicked BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ─── Loyalty ────────────────────────────────────────────────────────────────

CREATE TABLE store.loyalty_points (
    id SERIAL PRIMARY KEY,
    customer_id INT UNIQUE NOT NULL REFERENCES store.customers(id),
    balance INT NOT NULL DEFAULT 0,
    lifetime_earned INT NOT NULL DEFAULT 0,
    tier VARCHAR(20) DEFAULT 'bronze',
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.loyalty_transactions (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    points INT NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('earned', 'redeemed', 'expired', 'adjusted')),
    description VARCHAR(255),
    order_id INT REFERENCES store.orders(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- ─── Subscriptions ──────────────────────────────────────────────────────────

CREATE TABLE store.subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    interval VARCHAR(20) NOT NULL CHECK (interval IN ('monthly', 'quarterly', 'yearly')),
    features JSONB,
    is_active BOOLEAN DEFAULT true
);

CREATE TABLE store.subscriptions (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES store.customers(id),
    plan_id INT NOT NULL REFERENCES store.subscription_plans(id),
    status VARCHAR(30) DEFAULT 'active',
    current_period_start TIMESTAMP,
    current_period_end TIMESTAMP,
    canceled_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ─── Audit ──────────────────────────────────────────────────────────────────

CREATE TABLE store.audit_logs (
    id SERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id INT NOT NULL,
    action VARCHAR(20) NOT NULL,
    actor_type VARCHAR(20),
    actor_id INT,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE store.api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(255) NOT NULL,
    permissions JSONB DEFAULT '[]',
    last_used_at TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- DATA INSERTION
-- ═══════════════════════════════════════════════════════════════════════════════

-- Countries
INSERT INTO store.countries (code, name) VALUES
('US','United States'),('GB','United Kingdom'),('CA','Canada'),('AU','Australia'),
('DE','Germany'),('FR','France'),('JP','Japan'),('SG','Singapore'),
('IN','India'),('BR','Brazil'),('NL','Netherlands'),('SE','Sweden'),
('KR','South Korea'),('IT','Italy'),('ES','Spain'),('MX','Mexico'),
('NZ','New Zealand'),('IE','Ireland'),('CH','Switzerland'),('NO','Norway');

-- Currencies
INSERT INTO store.currencies (code, name, symbol) VALUES
('USD','US Dollar','$'),('GBP','British Pound','£'),('EUR','Euro','€'),
('AUD','Australian Dollar','A$'),('CAD','Canadian Dollar','C$'),
('JPY','Japanese Yen','¥'),('SGD','Singapore Dollar','S$'),
('INR','Indian Rupee','₹'),('BRL','Brazilian Real','R$'),('CHF','Swiss Franc','CHF');

-- Departments
INSERT INTO store.departments (name, description) VALUES
('Engineering','Software development and infrastructure'),
('Marketing','Brand, growth, and content'),
('Sales','Revenue and partnerships'),
('Support','Customer success and help desk'),
('Operations','Logistics and fulfillment'),
('Finance','Accounting and payroll'),
('HR','People and culture'),
('Product','Product management and design');

-- Roles
INSERT INTO store.roles (name, permissions) VALUES
('admin','{"all": true}'),
('manager','{"read": true, "write": true, "delete": false}'),
('agent','{"read": true, "write": true}'),
('viewer','{"read": true}'),
('warehouse_staff','{"inventory": true, "shipping": true}');

-- Categories (hierarchical)
INSERT INTO store.categories (name, parent_id, slug, description) VALUES
('Electronics', NULL, 'electronics', 'Electronic devices and accessories'),
('Clothing', NULL, 'clothing', 'Apparel and fashion'),
('Home & Garden', NULL, 'home-garden', 'Home improvement and garden supplies'),
('Books', NULL, 'books', 'Physical and digital books'),
('Sports', NULL, 'sports', 'Sporting goods and equipment'),
('Health', NULL, 'health', 'Health and wellness products'),
('Toys', NULL, 'toys', 'Toys and games'),
('Automotive', NULL, 'automotive', 'Car parts and accessories');

INSERT INTO store.categories (name, parent_id, slug, description) VALUES
('Laptops', 1, 'laptops', 'Portable computers'),
('Smartphones', 1, 'smartphones', 'Mobile phones'),
('Headphones', 1, 'headphones', 'Audio accessories'),
('Cameras', 1, 'cameras', 'Digital cameras and lenses'),
('Men''s Wear', 2, 'mens-wear', 'Men''s clothing'),
('Women''s Wear', 2, 'womens-wear', 'Women''s clothing'),
('Kids'' Wear', 2, 'kids-wear', 'Children''s clothing'),
('Furniture', 3, 'furniture', 'Indoor and outdoor furniture'),
('Kitchen', 3, 'kitchen', 'Kitchen appliances and tools'),
('Garden Tools', 3, 'garden-tools', 'Gardening equipment'),
('Fiction', 4, 'fiction', 'Fiction books'),
('Non-Fiction', 4, 'non-fiction', 'Non-fiction books'),
('Technical', 4, 'technical', 'Programming and engineering books'),
('Running', 5, 'running', 'Running shoes and gear'),
('Cycling', 5, 'cycling', 'Bikes and cycling accessories'),
('Yoga', 5, 'yoga', 'Yoga mats and accessories'),
('Supplements', 6, 'supplements', 'Vitamins and supplements'),
('Fitness Equipment', 6, 'fitness-equipment', 'Home gym equipment');

-- Tags
INSERT INTO store.tags (name, slug) VALUES
('bestseller','bestseller'),('new-arrival','new-arrival'),('sale','sale'),
('eco-friendly','eco-friendly'),('premium','premium'),('limited-edition','limited-edition'),
('handmade','handmade'),('organic','organic'),('vegan','vegan'),('wireless','wireless'),
('waterproof','waterproof'),('lightweight','lightweight'),('durable','durable'),
('gift-idea','gift-idea'),('bundle','bundle');

-- Shipping carriers
INSERT INTO store.shipping_carriers (name, tracking_url_template) VALUES
('FedEx','https://www.fedex.com/fedextrack/?trknbr={tracking}'),
('UPS','https://www.ups.com/track?tracknum={tracking}'),
('DHL','https://www.dhl.com/en/express/tracking.html?AWB={tracking}'),
('USPS','https://tools.usps.com/go/TrackConfirmAction?tLabels={tracking}'),
('Amazon Logistics','https://track.amazon.com/tracking/{tracking}');

-- Payment methods
INSERT INTO store.payment_methods (name, provider) VALUES
('Credit Card','stripe'),('Debit Card','stripe'),('PayPal','paypal'),
('Apple Pay','stripe'),('Google Pay','stripe'),('Bank Transfer','manual'),
('Buy Now Pay Later','afterpay');

-- Suppliers
INSERT INTO store.suppliers (name, contact_email, contact_phone, country_id, rating) VALUES
('TechWorld Electronics','orders@techworld.com','+1-555-0101',1,4.5),
('FashionFirst Ltd','supply@fashionfirst.co.uk','+44-20-5550102',2,4.2),
('HomeStyle Inc','b2b@homestyle.com','+1-555-0103',1,4.0),
('Pacific Trade Co','sales@pacifictrade.com.au','+61-2-5550104',4,3.8),
('Euro Goods GmbH','handel@eurogoods.de','+49-30-5550105',5,4.3),
('Nordic Supply AB','info@nordicsupply.se','+46-8-5550106',12,4.7),
('Asia Direct','wholesale@asiadirect.sg','+65-5550107',8,4.1),
('Green Earth Products','eco@greenearth.ca','+1-555-0108',3,4.6),
('SportMax','bulk@sportmax.com','+1-555-0109',1,4.4),
('BookHouse Publishing','orders@bookhouse.com','+1-555-0110',1,4.8);

-- Warehouses
INSERT INTO store.warehouses (name, address, city, country_id, capacity) VALUES
('US East Hub','100 Warehouse Blvd','Newark',1,50000),
('US West Hub','200 Distribution Ave','Los Angeles',1,45000),
('EU Central','50 Lager Strasse','Frankfurt',5,35000),
('UK Depot','10 Logistics Park','Manchester',2,25000),
('APAC Hub','88 Supply Chain Rd','Singapore',8,30000);

-- Segments
INSERT INTO store.segments (name, description, criteria) VALUES
('VIP Customers','Customers with lifetime spend > $5000','{"min_lifetime_spend": 5000}'),
('New Customers','Registered in the last 30 days','{"registered_within_days": 30}'),
('At Risk','No order in 90 days','{"no_order_days": 90}'),
('Frequent Buyers','5+ orders in last 6 months','{"min_orders_6m": 5}'),
('High Value','Average order > $200','{"min_avg_order": 200}');

-- Subscription plans
INSERT INTO store.subscription_plans (name, description, price, interval, features) VALUES
('Basic','Essential perks','9.99','monthly','{"free_shipping": true, "early_access": false}'),
('Premium','Full benefits','24.99','monthly','{"free_shipping": true, "early_access": true, "priority_support": true}'),
('Annual Basic','Essential perks, annual','99.99','yearly','{"free_shipping": true, "early_access": false}'),
('Annual Premium','Full benefits, annual','249.99','yearly','{"free_shipping": true, "early_access": true, "priority_support": true, "exclusive_deals": true}');

-- Knowledge base categories
INSERT INTO store.knowledge_base_categories (name, slug, sort_order) VALUES
('Getting Started','getting-started',1),
('Orders & Shipping','orders-shipping',2),
('Returns & Refunds','returns-refunds',3),
('Account & Security','account-security',4),
('Payments','payments',5);

-- Knowledge base articles
INSERT INTO store.knowledge_base_articles (category_id, title, slug, body, is_published, view_count) VALUES
(1,'How to Create an Account','create-account','Step by step guide to creating your account...',true,1520),
(1,'Setting Up Your Profile','setup-profile','Customize your profile settings...',true,890),
(2,'Tracking Your Order','track-order','How to track your shipment in real time...',true,3200),
(2,'Shipping Policies','shipping-policies','Our shipping options and delivery times...',true,2100),
(2,'International Shipping','international-shipping','Shipping to countries outside the US...',true,1450),
(3,'How to Return an Item','return-item','Initiate a return in 3 easy steps...',true,4500),
(3,'Refund Processing Times','refund-times','When to expect your refund...',true,3800),
(4,'Resetting Your Password','reset-password','Forgot your password? Here is how to reset...',true,5200),
(4,'Two-Factor Authentication','2fa-setup','Secure your account with 2FA...',true,980),
(5,'Accepted Payment Methods','payment-methods','We accept the following payment methods...',true,2900),
(5,'Payment Failed','payment-failed','Troubleshooting failed payments...',true,1800);

-- ─── Generate Customers (500) ───────────────────────────────────────────────

INSERT INTO store.customers (email, first_name, last_name, phone, date_of_birth, is_active, email_verified, created_at)
SELECT
    'customer' || n || '@example.com',
    (ARRAY['James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','David','Elizabeth',
           'William','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Charles','Karen',
           'Christopher','Lisa','Daniel','Nancy','Matthew','Betty','Anthony','Margaret','Mark','Sandra',
           'Emma','Oliver','Ava','Liam','Sophia','Noah','Isabella','Ethan','Mia','Lucas'])[1 + (n % 40)],
    (ARRAY['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
           'Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
           'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Robinson',
           'Walker','Young','Allen','King','Wright','Scott','Torres','Nguyen','Hill','Flores'])[1 + ((n * 7) % 40)],
    '+1-555-' || LPAD((1000 + n)::text, 4, '0'),
    '1970-01-01'::date + (n * 7 % 15000) * INTERVAL '1 day',
    n % 20 != 0,
    n % 3 != 0,
    NOW() - (n * 3 % 730) * INTERVAL '1 day'
FROM generate_series(1, 500) AS n;

-- Customer addresses (700+)
INSERT INTO store.customer_addresses (customer_id, address_type, line1, city, state, postal_code, country_id, is_default)
SELECT
    c.id,
    CASE WHEN n = 1 THEN 'shipping' ELSE 'billing' END,
    (100 + c.id * n) || ' ' || (ARRAY['Main St','Oak Ave','Elm Dr','Pine Rd','Maple Ln','Cedar Ct','Birch Way','Willow Blvd'])[1 + (c.id % 8)],
    (ARRAY['New York','Los Angeles','Chicago','Houston','Phoenix','Philadelphia','San Antonio','San Diego','Dallas','San Jose',
           'Austin','Jacksonville','Fort Worth','Columbus','Charlotte','Indianapolis','San Francisco','Seattle','Denver','Boston'])[1 + (c.id % 20)],
    (ARRAY['NY','CA','IL','TX','AZ','PA','TX','CA','TX','CA','TX','FL','TX','OH','NC','IN','CA','WA','CO','MA'])[1 + (c.id % 20)],
    LPAD((10000 + c.id * 13 % 90000)::text, 5, '0'),
    1,
    n = 1
FROM store.customers c, generate_series(1, 2) AS n
WHERE c.id <= 350
UNION ALL
SELECT
    c.id, 'shipping',
    (200 + c.id) || ' High Street',
    (ARRAY['London','Manchester','Birmingham','Leeds','Glasgow','Edinburgh','Liverpool','Bristol'])[1 + (c.id % 8)],
    NULL,
    (ARRAY['SW1A 1AA','M1 1AE','B1 1AA','LS1 1BA','G1 1AA','EH1 1AA','L1 1AA','BS1 1AA'])[1 + (c.id % 8)],
    2,
    true
FROM store.customers c
WHERE c.id > 350;

-- Customer preferences
INSERT INTO store.customer_preferences (customer_id, newsletter_opt_in, sms_opt_in, preferred_currency_id, preferred_language)
SELECT
    id,
    id % 3 = 0,
    id % 5 = 0,
    CASE WHEN id <= 350 THEN 1 WHEN id <= 400 THEN 2 ELSE (1 + id % 7) END,
    CASE WHEN id % 10 = 0 THEN 'fr' WHEN id % 12 = 0 THEN 'de' WHEN id % 15 = 0 THEN 'ja' ELSE 'en' END
FROM store.customers;

-- Customer segments
INSERT INTO store.customer_segments (customer_id, segment_id)
SELECT c.id, s.id
FROM store.customers c
CROSS JOIN store.segments s
WHERE (c.id + s.id) % 7 = 0;

-- ─── Generate Products (200) ────────────────────────────────────────────────

INSERT INTO store.products (sku, name, description, category_id, supplier_id, price, cost, weight_kg, is_active, is_featured, created_at)
SELECT
    'SKU-' || LPAD(n::text, 5, '0'),
    (ARRAY['Pro','Ultra','Max','Eco','Smart','Elite','Lite','Classic','Advanced','Essential'])[1 + (n % 10)] || ' ' ||
    (ARRAY['Widget','Gadget','Device','Tool','Kit','Pack','Set','Bundle','System','Unit'])[1 + ((n * 3) % 10)] || ' ' ||
    (ARRAY['Alpha','Beta','Gamma','Delta','Omega','Prime','Plus','Neo','X','Z'])[1 + ((n * 7) % 10)],
    'High-quality product with premium features. Designed for everyday use with durability in mind. ' || n,
    (ARRAY[9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26])[1 + (n % 18)],
    1 + (n % 10),
    (10 + (n * 17 % 500))::decimal(10,2),
    (5 + (n * 11 % 300))::decimal(10,2),
    (0.1 + (n * 3 % 50) * 0.1)::decimal(6,3),
    n % 15 != 0,
    n % 12 = 0,
    NOW() - (n * 2 % 365) * INTERVAL '1 day'
FROM generate_series(1, 200) AS n;

-- Product images (400)
INSERT INTO store.product_images (product_id, url, alt_text, sort_order, is_primary)
SELECT
    p.id,
    'https://images.example.com/products/' || p.sku || '_' || n || '.jpg',
    p.name || ' - Image ' || n,
    n,
    n = 1
FROM store.products p, generate_series(1, 2) AS n;

-- Product tags
INSERT INTO store.product_tags (product_id, tag_id)
SELECT p.id, t.id
FROM store.products p
CROSS JOIN store.tags t
WHERE (p.id + t.id * 3) % 11 = 0;

-- Supplier products
INSERT INTO store.supplier_products (supplier_id, product_id, supplier_sku, lead_time_days, min_order_quantity)
SELECT
    p.supplier_id,
    p.id,
    'SUP-' || p.supplier_id || '-' || p.id,
    3 + (p.id % 14),
    1 + (p.id % 5) * 5
FROM store.products p;

-- Inventory
INSERT INTO store.inventory (product_id, warehouse_id, quantity, reserved_quantity, reorder_point)
SELECT
    p.id,
    w.id,
    50 + (p.id * w.id % 500),
    (p.id * w.id % 20),
    10 + (p.id % 30)
FROM store.products p
CROSS JOIN store.warehouses w
WHERE (p.id + w.id) % 3 = 0;

-- Price history (1000+)
INSERT INTO store.price_history (product_id, old_price, new_price, changed_by, changed_at)
SELECT
    p.id,
    p.price * (0.8 + (n * 0.1)),
    p.price * (0.85 + (n * 0.05)),
    'system',
    NOW() - ((200 - p.id) + n * 30) * INTERVAL '1 day'
FROM store.products p, generate_series(1, 5) AS n
WHERE p.id <= 200;

-- ─── Generate Orders (2000) ─────────────────────────────────────────────────

INSERT INTO store.orders (order_number, customer_id, status, subtotal, discount_amount, shipping_cost, tax_amount, total, currency_id, created_at)
SELECT
    'ORD-' || LPAD(n::text, 6, '0'),
    1 + (n * 7 % 500),
    (ARRAY['pending','processing','shipped','delivered','delivered','delivered','delivered','canceled','refunded'])[1 + (n % 9)],
    (50 + (n * 13 % 500))::decimal(10,2),
    CASE WHEN n % 5 = 0 THEN (5 + n % 20)::decimal(10,2) ELSE 0 END,
    CASE WHEN n % 3 = 0 THEN 0 ELSE (5 + n % 15)::decimal(10,2) END,
    ((50 + (n * 13 % 500)) * 0.08)::decimal(10,2),
    ((50 + (n * 13 % 500)) * 1.08 + CASE WHEN n % 3 = 0 THEN 0 ELSE (5 + n % 15) END - CASE WHEN n % 5 = 0 THEN (5 + n % 20) ELSE 0 END)::decimal(10,2),
    1,
    NOW() - (n * 0.35)::int * INTERVAL '1 day'
FROM generate_series(1, 2000) AS n;

-- Order items (5000+)
INSERT INTO store.order_items (order_id, product_id, quantity, unit_price, total_price, discount_amount)
SELECT
    o.id,
    1 + ((o.id * item_n * 13) % 200),
    1 + (o.id * item_n % 4),
    p.price,
    p.price * (1 + (o.id * item_n % 4)),
    0
FROM store.orders o
CROSS JOIN generate_series(1, 3) AS item_n
JOIN store.products p ON p.id = 1 + ((o.id * item_n * 13) % 200)
WHERE item_n <= 1 + (o.id % 3);

-- Order status history
INSERT INTO store.order_status_history (order_id, old_status, new_status, changed_by, created_at)
SELECT
    o.id,
    NULL,
    'pending',
    'system',
    o.created_at
FROM store.orders o
UNION ALL
SELECT
    o.id,
    'pending',
    'processing',
    'system',
    o.created_at + INTERVAL '1 hour'
FROM store.orders o
WHERE o.status IN ('processing','shipped','delivered')
UNION ALL
SELECT
    o.id,
    'processing',
    'shipped',
    'system',
    o.created_at + INTERVAL '2 day'
FROM store.orders o
WHERE o.status IN ('shipped','delivered')
UNION ALL
SELECT
    o.id,
    'shipped',
    'delivered',
    'system',
    o.created_at + INTERVAL '5 day'
FROM store.orders o
WHERE o.status = 'delivered';

-- Payments
INSERT INTO store.payments (order_id, payment_method_id, amount, currency_id, status, transaction_id, created_at)
SELECT
    o.id,
    1 + (o.id % 7),
    o.total,
    1,
    CASE WHEN o.status = 'canceled' THEN 'refunded' ELSE 'completed' END,
    'txn_' || md5(o.id::text || 'salt'),
    o.created_at
FROM store.orders o;

-- Shipping
INSERT INTO store.shipping (order_id, carrier_id, tracking_number, status, shipped_at, delivered_at, estimated_delivery, created_at)
SELECT
    o.id,
    1 + (o.id % 5),
    UPPER(md5(o.id::text)::varchar(12)),
    CASE
        WHEN o.status = 'delivered' THEN 'delivered'
        WHEN o.status = 'shipped' THEN 'in_transit'
        WHEN o.status = 'canceled' THEN 'canceled'
        ELSE 'pending'
    END,
    CASE WHEN o.status IN ('shipped','delivered') THEN o.created_at + INTERVAL '1 day' END,
    CASE WHEN o.status = 'delivered' THEN o.created_at + INTERVAL '4 day' END,
    (o.created_at + INTERVAL '5 day')::date,
    o.created_at
FROM store.orders o
WHERE o.status NOT IN ('pending');

-- Coupons
INSERT INTO store.coupons (code, description, discount_type, discount_value, min_order_amount, max_uses, used_count, valid_from, valid_until)
VALUES
('WELCOME10','10% off first order','percentage',10,50,NULL,342,NOW() - INTERVAL '1 year',NOW() + INTERVAL '1 year'),
('SAVE20','$20 off orders over $100','fixed',20,100,1000,567,NOW() - INTERVAL '6 month',NOW() + INTERVAL '6 month'),
('SUMMER25','Summer sale 25% off','percentage',25,0,500,489,NOW() - INTERVAL '2 month',NOW() + INTERVAL '1 month'),
('FREESHIP','Free shipping on all orders','fixed',15,0,NULL,891,NOW() - INTERVAL '3 month',NOW() + INTERVAL '9 month'),
('VIP30','VIP exclusive 30% off','percentage',30,200,100,45,NOW() - INTERVAL '1 month',NOW() + INTERVAL '2 month'),
('HOLIDAY50','Holiday special $50 off','fixed',50,150,200,178,NOW() - INTERVAL '1 month',NOW() + INTERVAL '1 month'),
('FLASH15','Flash sale 15% off','percentage',15,0,300,299,NOW() - INTERVAL '1 week',NOW() + INTERVAL '1 day'),
('LOYAL20','Loyalty reward $20','fixed',20,75,NULL,234,NOW() - INTERVAL '1 year',NOW() + INTERVAL '1 year');

-- Coupon usage
INSERT INTO store.coupon_usage (coupon_id, customer_id, order_id, used_at)
SELECT
    1 + (o.id % 8),
    o.customer_id,
    o.id,
    o.created_at
FROM store.orders o
WHERE o.id % 5 = 0
LIMIT 400;

-- Returns
INSERT INTO store.returns (order_id, customer_id, reason, status, refund_amount, created_at, resolved_at)
SELECT
    o.id,
    o.customer_id,
    (ARRAY['Defective product','Wrong item received','Changed mind','Size doesn''t fit','Not as described','Arrived damaged'])[1 + (o.id % 6)],
    (ARRAY['requested','approved','refunded','rejected'])[1 + (o.id % 4)],
    o.total * 0.8,
    o.created_at + INTERVAL '7 day',
    CASE WHEN o.id % 4 != 0 THEN o.created_at + INTERVAL '14 day' END
FROM store.orders o
WHERE o.status = 'delivered' AND o.id % 10 = 0
LIMIT 150;

-- Return items
INSERT INTO store.return_items (return_id, order_item_id, quantity, condition)
SELECT
    r.id,
    oi.id,
    1,
    (ARRAY['unopened','like_new','used','damaged'])[1 + (r.id % 4)]
FROM store.returns r
JOIN store.order_items oi ON oi.order_id = r.order_id
WHERE oi.id % 2 = 0;

-- ─── Carts & Wishlists ──────────────────────────────────────────────────────

INSERT INTO store.carts (customer_id, session_id, created_at)
SELECT
    id,
    'sess_' || md5(id::text || 'cart'),
    NOW() - (id % 30) * INTERVAL '1 day'
FROM store.customers
WHERE id <= 200;

INSERT INTO store.cart_items (cart_id, product_id, quantity, added_at)
SELECT
    c.id,
    1 + (c.id * item_n * 11 % 200),
    1 + (c.id % 3),
    c.created_at + item_n * INTERVAL '1 hour'
FROM store.carts c
CROSS JOIN generate_series(1, 3) AS item_n
WHERE item_n <= 1 + (c.id % 3);

INSERT INTO store.wishlists (customer_id, name, is_public, created_at)
SELECT
    id,
    CASE WHEN id % 3 = 0 THEN 'Birthday Ideas' WHEN id % 3 = 1 THEN 'My Wishlist' ELSE 'Gift List' END,
    id % 5 = 0,
    NOW() - (id % 180) * INTERVAL '1 day'
FROM store.customers
WHERE id <= 300;

INSERT INTO store.wishlist_items (wishlist_id, product_id, added_at)
SELECT
    w.id,
    1 + (w.id * item_n * 7 % 200),
    w.created_at + item_n * INTERVAL '1 day'
FROM store.wishlists w
CROSS JOIN generate_series(1, 4) AS item_n
WHERE item_n <= 2 + (w.id % 3)
ON CONFLICT (wishlist_id, product_id) DO NOTHING;

-- ─── Employees ──────────────────────────────────────────────────────────────

INSERT INTO store.employees (email, first_name, last_name, department_id, hire_date, salary, is_active)
SELECT
    'employee' || n || '@company.com',
    (ARRAY['Alex','Sam','Jordan','Taylor','Morgan','Casey','Riley','Quinn','Avery','Blake',
           'Cameron','Drew','Finley','Harper','Jesse','Kelly','Logan','Parker','Reese','Skyler'])[1 + (n % 20)],
    (ARRAY['Adams','Baker','Carter','Dixon','Evans','Foster','Grant','Hayes','Irwin','James',
           'Kent','Lang','Mason','Nash','Owen','Price','Quinn','Reed','Shaw','Turner'])[1 + ((n * 3) % 20)],
    1 + (n % 8),
    '2018-01-01'::date + (n * 47 % 2000) * INTERVAL '1 day',
    50000 + (n * 1337 % 80000),
    n % 12 != 0
FROM generate_series(1, 60) AS n;

INSERT INTO store.employee_roles (employee_id, role_id)
SELECT
    e.id,
    CASE
        WHEN e.id <= 5 THEN 1
        WHEN e.id <= 15 THEN 2
        WHEN e.id <= 40 THEN 3
        ELSE 4
    END
FROM store.employees e;

-- ─── Product Reviews (1500+) ────────────────────────────────────────────────

INSERT INTO store.product_reviews (product_id, customer_id, rating, title, body, is_verified_purchase, is_approved, created_at)
SELECT
    1 + (n * 7 % 200),
    1 + (n * 11 % 500),
    1 + (n % 5),
    (ARRAY['Great product!','Not bad','Exceeded expectations','Decent quality','Amazing value',
           'Would buy again','Disappointed','Perfect for my needs','Good but pricey','Solid choice'])[1 + (n % 10)],
    (ARRAY[
        'Really happy with this purchase. Works exactly as described.',
        'Decent quality for the price. Shipping was fast.',
        'This exceeded my expectations. Highly recommend to others.',
        'Average product. Nothing special but does the job.',
        'Absolutely love it! Best purchase I have made this year.',
        'Good quality but took a while to arrive.',
        'Not what I expected based on the description.',
        'Perfect! Exactly what I was looking for.',
        'Works well but could be better packaged.',
        'Outstanding quality and great customer service.'
    ])[1 + (n % 10)],
    n % 3 = 0,
    n % 5 != 0,
    NOW() - (n * 0.4)::int * INTERVAL '1 day'
FROM generate_series(1, 1500) AS n;

-- ─── Marketing ──────────────────────────────────────────────────────────────

INSERT INTO store.email_campaigns (name, subject, body_html, segment_id, status, scheduled_at, sent_at, created_at)
VALUES
('Welcome Series','Welcome to our store!','<h1>Welcome!</h1><p>Thanks for joining...</p>',2,'sent',NOW() - INTERVAL '30 day',NOW() - INTERVAL '30 day',NOW() - INTERVAL '31 day'),
('Summer Sale','Hot deals for summer!','<h1>Summer Sale</h1><p>Up to 50% off...</p>',NULL,'sent',NOW() - INTERVAL '14 day',NOW() - INTERVAL '14 day',NOW() - INTERVAL '15 day'),
('VIP Exclusive','Special offer just for you','<h1>VIP Deal</h1><p>30% off everything...</p>',1,'sent',NOW() - INTERVAL '7 day',NOW() - INTERVAL '7 day',NOW() - INTERVAL '8 day'),
('Win-back','We miss you!','<h1>Come back!</h1><p>Here is 20% off...</p>',3,'sent',NOW() - INTERVAL '3 day',NOW() - INTERVAL '3 day',NOW() - INTERVAL '4 day'),
('New Arrivals','Check out what is new','<h1>New Products</h1><p>Fresh arrivals this week...</p>',NULL,'scheduled',NOW() + INTERVAL '2 day',NULL,NOW()),
('Black Friday','Biggest sale of the year','<h1>Black Friday!</h1><p>Deals you cannot miss...</p>',NULL,'draft',NULL,NULL,NOW());

INSERT INTO store.email_sends (campaign_id, customer_id, status, opened_at, clicked_at, sent_at)
SELECT
    c.id,
    cust.id,
    CASE
        WHEN cust.id % 5 = 0 THEN 'bounced'
        WHEN cust.id % 3 = 0 THEN 'opened'
        ELSE 'sent'
    END,
    CASE WHEN cust.id % 3 = 0 THEN c.sent_at + (cust.id % 48) * INTERVAL '1 hour' END,
    CASE WHEN cust.id % 7 = 0 THEN c.sent_at + (cust.id % 72) * INTERVAL '1 hour' END,
    c.sent_at
FROM store.email_campaigns c
CROSS JOIN store.customers cust
WHERE c.status = 'sent' AND cust.id <= 100;

-- Notifications (2000+)
INSERT INTO store.notifications (customer_id, type, title, body, is_read, created_at)
SELECT
    1 + (n % 500),
    (ARRAY['order_update','promotion','review_response','shipping','loyalty','system'])[1 + (n % 6)],
    (ARRAY['Your order has shipped','Special offer for you','Someone replied to your review',
           'Delivery update','You earned points!','Account security update'])[1 + (n % 6)],
    'Notification details for item ' || n,
    n % 3 = 0,
    NOW() - (n * 0.2)::int * INTERVAL '1 day'
FROM generate_series(1, 2000) AS n;

-- ─── Support ────────────────────────────────────────────────────────────────

INSERT INTO store.support_tickets (ticket_number, customer_id, assigned_to, subject, priority, status, order_id, created_at, resolved_at)
SELECT
    'TKT-' || LPAD(n::text, 5, '0'),
    1 + (n * 7 % 500),
    CASE WHEN n % 3 = 0 THEN NULL ELSE 1 + (n % 60) END,
    (ARRAY['Order not received','Damaged item','Wrong size','Payment issue','Account locked',
           'Refund not processed','Missing items','Delivery delay','Product question','Billing error'])[1 + (n % 10)],
    (ARRAY['low','medium','medium','high','urgent'])[1 + (n % 5)],
    (ARRAY['open','open','in_progress','resolved','resolved','closed'])[1 + (n % 6)],
    CASE WHEN n % 2 = 0 THEN 1 + (n * 3 % 2000) END,
    NOW() - (n * 1.5)::int * INTERVAL '1 day',
    CASE WHEN n % 3 != 0 THEN NOW() - (n * 1.5 - 2)::int * INTERVAL '1 day' END
FROM generate_series(1, 300) AS n;

INSERT INTO store.ticket_comments (ticket_id, author_type, author_id, body, is_internal, created_at)
SELECT
    t.id,
    CASE WHEN comment_n = 1 THEN 'customer' ELSE 'employee' END,
    CASE WHEN comment_n = 1 THEN (SELECT customer_id FROM store.support_tickets WHERE id = t.id) ELSE 1 + (t.id % 60) END,
    CASE comment_n
        WHEN 1 THEN 'I need help with this issue. Please look into it.'
        WHEN 2 THEN 'Thank you for contacting us. Let me investigate this for you.'
        ELSE 'This has been resolved. Please let us know if you need anything else.'
    END,
    comment_n = 2 AND t.id % 4 = 0,
    t.created_at + comment_n * INTERVAL '4 hour'
FROM store.support_tickets t
CROSS JOIN generate_series(1, 3) AS comment_n
WHERE comment_n <= CASE WHEN t.status IN ('resolved','closed') THEN 3 ELSE 2 END;

-- ─── Analytics ──────────────────────────────────────────────────────────────

INSERT INTO store.sessions (session_id, customer_id, ip_address, user_agent, started_at, ended_at)
SELECT
    'sess_' || md5(n::text || 'session'),
    CASE WHEN n % 4 = 0 THEN NULL ELSE 1 + (n * 3 % 500) END,
    ('192.168.' || (n % 255) || '.' || ((n * 7) % 255))::inet,
    (ARRAY[
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36'
    ])[1 + (n % 4)],
    NOW() - (n * 0.1)::int * INTERVAL '1 day',
    NOW() - (n * 0.1)::int * INTERVAL '1 day' + (5 + n % 55) * INTERVAL '1 minute'
FROM generate_series(1, 3000) AS n;

INSERT INTO store.page_views (session_id, path, referrer, duration_seconds, created_at)
SELECT
    s.id,
    (ARRAY['/','/products','/products/' || (1 + s.id % 200),'/cart','/checkout',
           '/account','/orders','/search','/categories','/about'])[1 + (pv % 10)],
    CASE WHEN pv = 1 THEN (ARRAY['https://google.com','https://facebook.com','https://twitter.com',NULL])[1 + (s.id % 4)] END,
    2 + (s.id * pv % 120),
    s.started_at + pv * INTERVAL '30 second'
FROM store.sessions s
CROSS JOIN generate_series(1, 5) AS pv
WHERE s.id <= 2000 AND pv <= 2 + (s.id % 4);

INSERT INTO store.search_queries (customer_id, query_text, results_count, clicked_product_id, created_at)
SELECT
    CASE WHEN n % 3 = 0 THEN NULL ELSE 1 + (n * 7 % 500) END,
    (ARRAY['laptop','wireless headphones','running shoes','yoga mat','coffee maker',
           'backpack','smart watch','desk lamp','water bottle','phone case',
           'bluetooth speaker','gaming mouse','protein powder','kindle','sunglasses',
           'hoodie','mechanical keyboard','air purifier','standing desk','vitamins'])[1 + (n % 20)],
    (n * 13 % 50) + 1,
    CASE WHEN n % 2 = 0 THEN 1 + (n * 11 % 200) END,
    NOW() - (n * 0.15)::int * INTERVAL '1 day'
FROM generate_series(1, 2000) AS n;

-- Recommendations
INSERT INTO store.recommendations (customer_id, product_id, score, reason, is_clicked, created_at)
SELECT
    1 + (n % 500),
    1 + (n * 11 % 200),
    (0.5 + (n % 50) * 0.01)::decimal(5,4),
    (ARRAY['collaborative_filtering','content_based','trending','frequently_bought_together','based_on_history'])[1 + (n % 5)],
    n % 8 = 0,
    NOW() - (n * 0.05)::int * INTERVAL '1 day'
FROM generate_series(1, 3000) AS n;

-- ─── Loyalty ────────────────────────────────────────────────────────────────

INSERT INTO store.loyalty_points (customer_id, balance, lifetime_earned, tier, updated_at)
SELECT
    id,
    (id * 17 % 5000),
    (id * 17 % 5000) + (id * 23 % 3000),
    CASE
        WHEN (id * 17 % 5000) > 4000 THEN 'platinum'
        WHEN (id * 17 % 5000) > 2000 THEN 'gold'
        WHEN (id * 17 % 5000) > 500 THEN 'silver'
        ELSE 'bronze'
    END,
    NOW() - (id % 60) * INTERVAL '1 day'
FROM store.customers;

INSERT INTO store.loyalty_transactions (customer_id, points, type, description, order_id, created_at)
SELECT
    o.customer_id,
    (o.total)::int,
    'earned',
    'Points earned from order ' || o.order_number,
    o.id,
    o.created_at
FROM store.orders o
WHERE o.status = 'delivered'
UNION ALL
SELECT
    c.id,
    -(50 + c.id % 200),
    'redeemed',
    'Points redeemed for discount',
    NULL,
    NOW() - (c.id % 90) * INTERVAL '1 day'
FROM store.customers c
WHERE c.id % 4 = 0;

-- ─── Subscriptions ──────────────────────────────────────────────────────────

INSERT INTO store.subscriptions (customer_id, plan_id, status, current_period_start, current_period_end, canceled_at, created_at)
SELECT
    c.id,
    1 + (c.id % 4),
    CASE WHEN c.id % 8 = 0 THEN 'canceled' WHEN c.id % 12 = 0 THEN 'expired' ELSE 'active' END,
    NOW() - INTERVAL '15 day',
    NOW() + INTERVAL '15 day',
    CASE WHEN c.id % 8 = 0 THEN NOW() - (c.id % 30) * INTERVAL '1 day' END,
    NOW() - (60 + c.id % 300) * INTERVAL '1 day'
FROM store.customers c
WHERE c.id % 3 = 0;

-- ─── Audit Logs (2000) ──────────────────────────────────────────────────────

INSERT INTO store.audit_logs (entity_type, entity_id, action, actor_type, actor_id, old_values, new_values, ip_address, created_at)
SELECT
    (ARRAY['order','customer','product','payment','return'])[1 + (n % 5)],
    1 + (n * 7 % 500),
    (ARRAY['create','update','delete','status_change'])[1 + (n % 4)],
    CASE WHEN n % 3 = 0 THEN 'system' ELSE 'employee' END,
    CASE WHEN n % 3 = 0 THEN NULL ELSE 1 + (n % 60) END,
    CASE WHEN n % 4 = 1 THEN '{"status": "pending"}'::jsonb END,
    CASE WHEN n % 4 = 1 THEN '{"status": "processing"}'::jsonb ELSE '{}'::jsonb END,
    ('10.0.' || (n % 255) || '.' || ((n * 3) % 255))::inet,
    NOW() - (n * 0.3)::int * INTERVAL '1 day'
FROM generate_series(1, 2000) AS n;

-- API keys
INSERT INTO store.api_keys (name, key_hash, permissions, last_used_at, expires_at, is_active) VALUES
('Mobile App','$2b$12$abcdefghijklmnopqrstuv','["read:products","read:orders","write:cart"]',NOW() - INTERVAL '1 hour',NOW() + INTERVAL '1 year',true),
('Partner Integration','$2b$12$wxyzabcdefghijklmnopqr','["read:products","read:inventory"]',NOW() - INTERVAL '3 day',NOW() + INTERVAL '6 month',true),
('Internal Dashboard','$2b$12$123456789abcdefghijklm','["read:all","write:all"]',NOW() - INTERVAL '10 minute',NULL,true),
('Legacy System','$2b$12$oldkeyhashabcdefghijkl','["read:orders"]',NOW() - INTERVAL '90 day',NOW() - INTERVAL '30 day',false);

-- ─── Create Indexes for Performance ─────────────────────────────────────────

CREATE INDEX idx_customers_email ON store.customers(email);
CREATE INDEX idx_customers_created_at ON store.customers(created_at);
CREATE INDEX idx_orders_customer_id ON store.orders(customer_id);
CREATE INDEX idx_orders_status ON store.orders(status);
CREATE INDEX idx_orders_created_at ON store.orders(created_at);
CREATE INDEX idx_order_items_order_id ON store.order_items(order_id);
CREATE INDEX idx_order_items_product_id ON store.order_items(product_id);
CREATE INDEX idx_products_category_id ON store.products(category_id);
CREATE INDEX idx_products_supplier_id ON store.products(supplier_id);
CREATE INDEX idx_products_sku ON store.products(sku);
CREATE INDEX idx_inventory_product_id ON store.inventory(product_id);
CREATE INDEX idx_payments_order_id ON store.payments(order_id);
CREATE INDEX idx_shipping_order_id ON store.shipping(order_id);
CREATE INDEX idx_reviews_product_id ON store.product_reviews(product_id);
CREATE INDEX idx_reviews_customer_id ON store.product_reviews(customer_id);
CREATE INDEX idx_sessions_customer_id ON store.sessions(customer_id);
CREATE INDEX idx_page_views_session_id ON store.page_views(session_id);
CREATE INDEX idx_audit_logs_entity ON store.audit_logs(entity_type, entity_id);
CREATE INDEX idx_notifications_customer_id ON store.notifications(customer_id);
CREATE INDEX idx_support_tickets_customer_id ON store.support_tickets(customer_id);
CREATE INDEX idx_loyalty_transactions_customer_id ON store.loyalty_transactions(customer_id);

-- ─── Summary ────────────────────────────────────────────────────────────────

-- Run this to verify:
-- SELECT schemaname, count(*) as table_count FROM pg_tables WHERE schemaname = 'store' GROUP BY schemaname;
-- SELECT relname as table, n_live_tup as row_count FROM pg_stat_user_tables WHERE schemaname = 'store' ORDER BY n_live_tup DESC;
