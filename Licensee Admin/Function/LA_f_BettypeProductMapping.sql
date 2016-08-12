USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[LA_f_BettypeProductMapping] (
	 @Bettype	 	INT = 0
	,@ProductCodes VARCHAR(1000)	
	)
RETURNS @tbBettypeProduct TABLE (
	Bettype INT,ProductID INT
	)
AS
/*	Created: 20141111@Florent
	Task : Get bettype product mapping
	DB: DB052/bodb_Licensee
	Revisions:
		- 20150202@Patrick: Add more product: Bingo & Keno
		- 20150414@Jim: add MicroGaming
		- 20150714@Florent: Add product Gold Deluxe
		- 20150820@Florent: Add Bettrade and remove bettypes 901, 902, 903 in SB, BA
		- 20151012@Victor: Add product AG Casino Single Wallet
		- 20151201@Bravo: Change Product code: MGC -> MGCLC
		- 20160113@Bruce: Include new bettypes 2101-2399 for CS (OW RNG)
		- 20160224@Victor: Add product Cock Fighting [Redmine: 52452]
		- 20160318@Bruce: Add product Colossus bet
		- 20160422@Victor: Add product Voidbridge [Redmine: #55057]
		- 20160808@Bravo: #57972 - LA/ OWA - Change Commercial Terms for BetTrade
	Param's Explanation:

*/

BEGIN
	DECLARE @ProductList TABLE (ProductCode VARCHAR(10))

	INSERT INTO @ProductList (ProductCode)
	SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductCodes, ',')

    IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'SB')
	   --OR CHARINDEX('BA', @ProductCodes) <> 0
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 0
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid < 31
		  OR typeid BETWEEN 121 AND 999
		  OR typeid BETWEEN 1301 AND 1399)
		  AND typeid NOT IN (901, 902, 903, 904) -- Bettrade bettypes
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BA')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 3
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid < 31
		  OR typeid BETWEEN 121 AND 999
		  OR typeid BETWEEN 1301 AND 1399)
		  AND typeid NOT IN (901, 902, 903, 904) -- Bettrade bettypes
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'RB')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 1
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid IN (31, 32, 33, 41, 42, 43)
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'NG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 2
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 81 AND 120
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'LC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 4
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1101 AND 1199
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VS')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 5
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1201 AND 1299
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CS')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 6
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid IN (71, 72) OR typeid BETWEEN 2101 AND 2399)
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 7
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 73
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'KN')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 8
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1501 AND 1599
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'MGCLC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 14
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 2001 AND 2007
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END
    
    IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'MGCRNG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 17
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 2008 AND 2009
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'GD')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 11
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1701 AND 1799
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BT')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 13
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 901 AND 904
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'AGC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 10
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1801 AND 1899
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CF')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 19
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 1003
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CB')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 15
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 18000 AND 18006
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VB')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 22
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 4001 AND 7999
		  AND (@Bettype = 0 OR (@Bettype != 0 AND typeid = @Bettype))
	END

	RETURN
END
