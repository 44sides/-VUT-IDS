-- IDS project part4
-- Michal Findra xfindr00
-- Vladyslav Tverdokhlib xtverd01

-- drop triggers
DROP TRIGGER uzivatel_gen_PK;
DROP TRIGGER recenze_komentar_integrity;

-- drop procedures
DROP PROCEDURE nejdrazsi_pobyt_hostu;

-- drop sequences
DROP SEQUENCE uzivatel_seq;

-- drop materialized view
DROP MATERIALIZED VIEW zeme_sk;

------- 2. část -------
-- drop tables
DROP TABLE doporuceni CASCADE CONSTRAINTS;
DROP TABLE recenze CASCADE CONSTRAINTS;
DROP TABLE obdobi CASCADE CONSTRAINTS;
DROP TABLE rezervace CASCADE CONSTRAINTS;
DROP TABLE pobyt CASCADE CONSTRAINTS;
DROP TABLE host CASCADE CONSTRAINTS;
DROP TABLE uzivatel CASCADE CONSTRAINTS;
DROP TABLE pronajimatel CASCADE CONSTRAINTS;
DROP TABLE ubytovani CASCADE CONSTRAINTS;

-- create tables
CREATE TABLE uzivatel (
	ucet_id INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,
	jmeno VARCHAR(255) NOT NULL,
	prijmeni VARCHAR(255) NOT NULL,
	RC INT NOT NULL,
	adresa VARCHAR(255) NOT NULL,
	telefon VARCHAR(12) NOT NULL
);

CREATE TABLE host (
	uzivatel INT REFERENCES uzivatel(ucet_id) PRIMARY KEY, 
	datum_registrace DATE NOT NULL,
	pocet_ubytovani INT,
	overeny_uzivatel VARCHAR(3) NOT NULL,
	CHECK (overeny_uzivatel in ('ano','ne') AND POCET_UBYTOVANI >= 0 )
);

CREATE TABLE pronajimatel(
	uzivatel INT REFERENCES uzivatel(ucet_id) PRIMARY KEY,
	informace VARCHAR(255) ,
	reputace VARCHAR(255) NOT NULL,
	cas_odezvy VARCHAR(6),
	CHECK (cas_odezvy in ('dni','hodiny','minuty')),
	CHECK (reputace in ('vyborna','nadpriemerna','priemerna','podpriemerná','nizka'))
);

CREATE TABLE doporuceni (
	doporuceni_id INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,	
	pamatky VARCHAR(255),
	aktivity VARCHAR(255),
	restaurace VARCHAR(255),
	autopujcovny VARCHAR(255)
);

CREATE TABLE ubytovani (
	ubytovani_id INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,
	pronajimatel INT REFERENCES pronajimatel(uzivatel),
	typ VARCHAR(255) NOT NULL,
	cena_za_noc NUMBER(8,2),
	typ_slevy VARCHAR(255),
	zeme VARCHAR(255) NOT NULL,
	mesto VARCHAR(255) NOT NULL,
	popis VARCHAR(255),
	vybaveni VARCHAR(255),
	pravidla VARCHAR(255),
	bezpecnostni_prvky VARCHAR(255),
	doporuceni INT REFERENCES doporuceni(doporuceni_id),
	CHECK (cena_za_noc >= 0)
);

CREATE TABLE rezervace (
	rezervace_id INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,
	host INT REFERENCES host(uzivatel),
	suma NUMBER(8,2),
	datum DATE NOT NULL,
	CHECK (suma >= 0)
);

CREATE TABLE pobyt ( --weak of host
	pobyt_num INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,
	host REFERENCES host,
	ubytovani REFERENCES ubytovani,
	datum_od DATE NOT NULL,
	datum_do DATE NOT NULL,
	platba VARCHAR(255),
	uskutocnil_se VARCHAR(3)
);

CREATE TABLE recenze ( --weak of ubytovani
	recenze_num INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,
	ubytovani REFERENCES ubytovani,
	host REFERENCES host,
	komentar VARCHAR(255),
	hodnoceni SMALLINT,
	CHECK (hodnoceni>=0 AND hodnoceni <=10)
);

CREATE TABLE obdobi (
	obdobi_id INT GENERATED BY DEFAULT AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL PRIMARY KEY,
	datum_od DATE not NULL,
	datum_do DATE not NULL,
	sleva NUMBER(8,2),
	rezervace_num NOT NULL,
	ubytovani_num NOT NULL,
	FOREIGN KEY (ubytovani_num) REFERENCES ubytovani(ubytovani_id),
  	FOREIGN KEY (rezervace_num) REFERENCES rezervace(rezervace_id), 
	CHECK (sleva >= 0)
);

------- 4. část -------

-- DVA TRIGGERY
-- trigger pro automaticke generovani hodnot PK uzivatele.
CREATE SEQUENCE uzivatel_seq
START WITH 1;

CREATE OR REPLACE TRIGGER uzivatel_gen_PK
BEFORE INSERT ON uzivatel
FOR EACH ROW
BEGIN
:new.ucet_id := uzivatel_seq.nextval;
END uzivatel_gen_PK;
/
	       
-- trigger pro komentare. Komentar od neovereneho hosta nebude prijat a vynuluje se.
CREATE OR REPLACE TRIGGER recenze_komentar_integrity
BEFORE INSERT ON recenze
FOR EACH ROW
declare status varchar(3);
BEGIN
IF (:new.komentar IS NOT NULL) THEN
select distinct overeny_uzivatel into status FROM host WHERE uzivatel = :new.host;
if status = 'ne' then
:new.komentar := NULL;
end if;
END IF;
END recenze_komentar_integrity;
/

-- DVE PROCEDURY
SET serveroutput ON;
-- Nejdrazsi pobyt urciteho hostu, ktery se uskutecnil.
CREATE OR REPLACE PROCEDURE nejdrazsi_pobyt_hostu (host_id in INT)
    IS 
    CURSOR kurz IS SELECT distinct r.host, u.cena_za_noc, o.datum_od, o.datum_do, o.sleva, p.uskutocnil_se, p.pobyt_num 
    FROM rezervace r JOIN obdobi o ON r.rezervace_id = o.rezervace_num 
    JOIN ubytovani u ON o.ubytovani_num = u.ubytovani_id 
    JOIN pobyt p ON p.host=r.host AND p.ubytovani=o.ubytovani_num;
    kurzrow kurz%ROWTYPE;
    koncova_cena NUMBER;
    max_cena NUMBER;
    max_pobyt INT;
    host_check INT;
    host_error exception;
    pobyt_error exception;
BEGIN
    koncova_cena := 0;
    max_cena := 0;
    
    select count(uzivatel) into host_check from host where uzivatel = host_id;
    IF host_check = 0 THEN
    RAISE host_error;
    END IF;
    
    OPEN kurz;
    LOOP
    FETCH kurz INTO kurzrow;
    EXIT WHEN kurz%NOTFOUND;
    
    IF (kurzrow.host = host_id AND kurzrow.uskutocnil_se = 'ano') THEN
    koncova_cena := (kurzrow.cena_za_noc * (kurzrow.datum_do - kurzrow.datum_od) - kurzrow.sleva);
    END IF;
    if (max_cena < koncova_cena) then
    max_cena := koncova_cena;
    max_pobyt := kurzrow.pobyt_num;
    end if;
    
    END LOOP;
    
    CLOSE kurz;
    IF max_cena = 0 THEN
    RAISE pobyt_error;
    END IF;
    
    dbms_output.put_line('Nejdrazsi pobyt hostu id ' || host_id || ' je id ' || max_pobyt || ' (' || max_cena || ').');

    EXCEPTION
    WHEN host_error THEN
        dbms_output.put_line('CHYBA: Host s danym ID neexistuje.');
    WHEN pobyt_error THEN
        dbms_output.put_line('CHYBA: Host nema pobyty, ktere se uskutecnily');
    WHEN OTHERS THEN
        dbms_output.put_line('CHYBA: Ostatni chyba.');
END;
/

-- ----------------


-- INITILIZE VALUES

-- insert into uzivatel
INSERT INTO uzivatel VALUES (DEFAULT, 'Oleg', 'Starý','100403001', 'Mlynská 12 Praha', '420696969696');
INSERT INTO uzivatel VALUES (DEFAULT, 'Milan', 'Suchý','9109120009', 'Družstevná 125 Michalovce', '420555555555');
INSERT INTO uzivatel VALUES (DEFAULT, 'Peter', 'Dvořák','7704260080', 'Zimná 444 Bratislava', '421353696787');
INSERT INTO uzivatel VALUES (DEFAULT, 'Igor', 'Mokrý','6408140079', 'Športová 123 Košice', '421747585212');

INSERT INTO uzivatel VALUES (DEFAULT, 'Jan', 'Novák','520606007', 'Lesná 665 Letanovce', '421555222555');
INSERT INTO uzivatel VALUES (DEFAULT, 'Jerguš', 'Chudobný','420213008', 'Mestská 222 Kežmarok', '421111444777');
INSERT INTO uzivatel VALUES (15, 'Ivan', 'Bohatý','340608010', 'Jarná 8 Prešov', '420999666333'); -- id ma byt 7 diky triggeru
INSERT INTO uzivatel VALUES (DEFAULT, 'Samuel', 'Čierny','8511250154', 'Jarná 8 Prešov', '420111222111');
INSERT INTO uzivatel VALUES (DEFAULT, 'Adam', 'Modrý','9702110253', 'Jesenná 585 Žilina', '421555444212');
--select ucet_id from uzivatel;
	       
--insert into pronajimatel
INSERT INTO pronajimatel VALUES (1, 'ziadne', 'vyborna', 'minuty');
INSERT INTO pronajimatel VALUES (2, 'kontaktovat skor vopred', 'nadpriemerna', 'hodiny');
INSERT INTO pronajimatel VALUES (3, 'ziadne', 'nizka', 'dni');
INSERT INTO pronajimatel VALUES (4, 'ziadne', 'vyborna', 'dni');

--insert into host
INSERT INTO host VALUES (5, DATE '2010-10-10', 1, 'ano' );
INSERT INTO host VALUES (6, DATE '2018-01-06', 2, 'ano' );
INSERT INTO host VALUES (7, DATE '2016-08-26', 5, 'ne' );
INSERT INTO host VALUES (8, DATE '2020-12-23', 2, 'ne' );
INSERT INTO host VALUES (9, DATE '2016-05-17', 10, 'ano' );
INSERT INTO host VALUES (4, DATE '2019-02-22', 1, 'ne' );

--insert into doporuceni
INSERT INTO doporuceni VALUES (DEFAULT, 'hrad, kastiel, muzeum', 'plavaren', 'Cin-cin, Hradna r.', '');
INSERT INTO doporuceni VALUES (DEFAULT, 'pamatnik, park', 'lezecka stena, bangee-jump', 'Burger r., Kebab r.', 'Ford požičovňa');
INSERT INTO doporuceni VALUES (DEFAULT, 'muzeum, hrad, bane', 'vystava umenia, ihrisko', 'Hodovna, Koliba', 'požičovňa Suchy');
INSERT INTO doporuceni VALUES (DEFAULT, 'hradby, hladomorna', 'plavaren, skokansky mostik', 'Pizzeria Luccia, Kebab do ruky', '');

--insert into ubytovani
INSERT INTO ubytovani VALUES (DEFAULT, 1, 'dom',15.75,'žiadna', 'Česko','Praha','dlhy popis','izba(2x postel), kuchynka, kuplka','zakaz fajcit vnutri','hasiaci pristroj',1);
INSERT INTO ubytovani VALUES (DEFAULT, 2, 'chata',50,'sezonna', 'Slovensko','Michalovce','kratky popis','izby(3 x 2x postel), kuchynka, kuplka','zakaz fajcit vnutri','hasiaci pristroj, unikove schody',2);
INSERT INTO ubytovani VALUES (DEFAULT, 3, 'izba',36,'žiadna', 'Slovensko','Bratislava','popis','1x postel, WC','zakaz zvierata','',3);
INSERT INTO ubytovani VALUES (DEFAULT, 4, 'dom',200,'dlhodoba', 'Slovensko','Košice','3 poschodovy dom','kuchyna, bazen, wellness','ziadne','hasiaci pristoj, detektor dymu',4);
INSERT INTO ubytovani VALUES (DEFAULT, 4, 'dom',500,'žiadna', 'Slovensko','Margecany','Vila na periferii','kuchyna, bazen, wellness, herna','ziadne','hasiaci pristoj, detektor dymu',4);

--insert into rezervace 
INSERT INTO rezervace VALUES (DEFAULT, 5, 47.25, DATE '2021-4-1');
INSERT INTO rezervace VALUES (DEFAULT, 5, 40, DATE '2021-4-1');
INSERT INTO rezervace VALUES (DEFAULT, 6, 5000, DATE '2021-4-2');
INSERT INTO rezervace VALUES (DEFAULT, 7, 2100, DATE '2021-2-20'); -- rezervace dvou obdobi zaroven s celkovou sumou.

--insert into obdobi
INSERT INTO obdobi VALUES (DEFAULT, DATE '2021-4-5', DATE '2021-4-8', 0, 1, 1);
INSERT INTO obdobi VALUES (DEFAULT, DATE '2021-10-1', DATE '2021-10-2', 10, 2, 2);
INSERT INTO obdobi VALUES (DEFAULT, DATE '2021-12-22', DATE '2022-1-1', 0, 3, 5);
INSERT INTO obdobi VALUES (DEFAULT, DATE '2021-3-5', DATE '2021-3-8', 0, 4, 4);
INSERT INTO obdobi VALUES (DEFAULT, DATE '2021-3-9', DATE '2021-3-12', 0, 4, 5);

--insert into recenze	       
--select uzivatel, overeny_uzivatel from host; --seznam vsech hostu.
INSERT INTO recenze VALUES (DEFAULT, 1, 5, 'vyborne, som uplne spokojny', '5'); -- komentar od overeneho hosta.
INSERT INTO recenze VALUES (DEFAULT, 2, 5, 'priemerne ubytovanie', '3'); -- komentar od overeneho hosta.
INSERT INTO recenze VALUES (DEFAULT, 5, 6, 'za tu cenu to nestoji', '2'); -- komentar od overeneho hosta.
INSERT INTO recenze VALUES (DEFAULT, 5, 7, 'byla to nezapomenutelná párty a vila byla na to ideální', '10'); -- komentar od neovereneho hosta. Komentar bude vynulovan.
--select host, komentar from recenze; -- seznam vsech komentaru.

--insert into pobyt
INSERT INTO pobyt VALUES (DEFAULT, 5, 1, DATE '2021-4-5', DATE '2021-4-8', 'kartou', 'ano' ); -- host 5. (47.25). Drazsi pobyt. 
INSERT INTO pobyt VALUES (DEFAULT, 5, 2, DATE '2021-10-1', DATE '2021-10-2', 'hotovosť', 'ano' ); -- host 5. (40).
exec  nejdrazsi_pobyt_hostu(5);
INSERT INTO pobyt VALUES (DEFAULT, 6, 5, DATE '2021-12-22', DATE '2022-1-1', 'šek', 'ano' ); -- host 6 ma jeden pobyt.

INSERT INTO pobyt VALUES (DEFAULT, 7, 4, DATE '2021-3-5', DATE '2021-3-8', 'ne', 'ano' ); -- host 7. (600). Drazsi pobyt, protoze se uskutecnil.
INSERT INTO pobyt VALUES (DEFAULT, 7, 5, DATE '2021-3-9', DATE '2021-3-12', 'kartou', 'ne' ); -- host 7. (1500).
exec  nejdrazsi_pobyt_hostu(7);
--CHYBA: Host nema pobyty, ktere se uskutecnily--
exec  nejdrazsi_pobyt_hostu(9);
--CHYBA: Host s danym ID neexistuje--ID patri pronajimateli.
exec  nejdrazsi_pobyt_hostu(1);

/* dokumentace link: https://www.overleaf.com/2176643837xxcrwtmhwxzs */

/*
Zadanie:
4. SQL skript pro vytvoření pokročilých objektů schématu databáze – SQL skript, který nejprve vytvoří 
    základní objekty schéma databáze a naplní tabulky ukázkovými daty (stejně jako skript v bodě 2),
    a poté zadefinuje či vytvoří pokročilá omezení či objekty databáze dle upřesňujících požadavků zadání.
    Dále skript bude obsahovat ukázkové příkazy manipulace dat a dotazy demonstrující použití výše zmiňovaných 
    omezení a objektů tohoto skriptu (např. pro demonstraci použití indexů zavolá nejprve skript EXPLAIN PLAN na dotaz 
    bez indexu, poté vytvoří index, a nakonec zavolá EXPLAIN PLAN na dotaz s indexem).

SQL skript v poslední části projektu musí obsahovat vše z následujících

    vytvoření alespoň dvou netriviálních uložených procedur vč. jejich předvedení, 
    ve kterých se musí (dohromady) vyskytovat alespoň jednou kurzor, ošetření výjimek a použití proměnné s datovým typem 
    odkazujícím se na řádek či typ sloupce tabulky (table_name.column_name%TYPE nebo table_name%ROWTYPE),

    explicitní vytvoření alespoň jednoho indexu tak, aby pomohl optimalizovat zpracování dotazů, přičemž musí být uveden 
    také příslušný dotaz, na který má index vliv, a v dokumentaci popsán způsob využití indexu v tomto dotazy 
    (toto lze zkombinovat s EXPLAIN PLAN, vizte dále),

    alespoň jedno použití EXPLAIN PLAN pro výpis plánu provedení databazového dotazu se spojením alespoň dvou tabulek,
    agregační funkcí a klauzulí GROUP BY, přičemž v dokumentaci musí být srozumitelně popsáno, jak proběhne dle toho výpisu
    plánu provedení dotazu, vč. objasnění použitých prostředků pro jeho urychlení (např. použití indexu, druhu spojení, atp.), 
    a dále musí být navrnut způsob, jak konkrétně by bylo možné dotaz dále urychlit (např. zavedením nového indexu), navržený 
    způsob proveden (např. vytvořen index), zopakován EXPLAIN PLAN a jeho výsledek porovnán s výsledkem před provedením navrženého 
    způsobu urychlení,

    definici přístupových práv k databázovým objektům pro druhého člena týmu,
    vytvořen alespoň jeden materializovaný pohled patřící druhému členu týmu a používající tabulky definované prvním členem týmu 
    (nutno mít již definována přístupová práva), vč. SQL příkazů/dotazů ukazujících, jak materializovaný pohled funguje,


5. Dokumentace popisující finální schéma databáze – Dokumentace popisující řešení ze skriptu v bodě 4 vč. jejich zdůvodnění 
    (např. popisuje výstup příkazu EXPLAIN PLAN bez indexu, důvod vytvoření zvoleného indexu, a výstup EXPLAIN PLAN s indexem, atd.).
*/




-- udelenie opravnení od autora tabuliek va databáze (xfindr00) pre druhého člena týmu (xtverd01)
GRANT ALL ON recenze TO xtverd01;
GRANT ALL ON obdobi TO xtverd01;
GRANT ALL ON rezervace TO xtverd01;
GRANT ALL ON pobyt TO xtverd01;
GRANT ALL ON host TO xtverd01;
GRANT ALL ON uzivatel TO xtverd01;
GRANT ALL ON pronajimatel TO xtverd01;
GRANT ALL ON ubytovani TO xtverd01;


--materialized view
CREATE MATERIALIZED VIEW zeme_sk AS 
	SELECT *
    	FROM ubytovani U WHERE U.zeme = 'Slovensko';

GRANT ALL ON zeme_sk TO xtverd01;
