CREATE TABLE COMPANY
(
  ID        INT PRIMARY KEY NOT NULL,
  NAME      TEXT            NOT NULL,
  AGE       INT             NOT NULL,
  ADDRESS   CHAR(50),
  SALARY    REAL,
  JOIN_DATE DATE
);

INSERT INTO COMPANY (ID, NAME, AGE, ADDRESS, SALARY, JOIN_DATE)
VALUES (1, 'Paul', 32, 'California', 20000.00, '2001-07-13'),
       (2, 'Allen', 25, 'Texas', 20000.00, '2007-12-13'),
       (3, 'Teddy', 23, 'Norway', 20000.00, '2007-12-13'),
       (4, 'Mark', 25, 'Rich-Mond ', 65000.00, '2007-12-13'),
       (5, 'David', 27, 'Texas', 85000.00, '2007-12-13');

DROP DATABASE IF EXISTS dvdrental;
CREATE DATABASE dvdrental;


