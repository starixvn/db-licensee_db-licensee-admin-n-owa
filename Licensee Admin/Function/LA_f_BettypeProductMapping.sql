/*<info serverAlias="DBLIC-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_Licensee
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
	DB: DBLIC.bodb_Licensee
	
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
		- 20160727@Jim:  LRF - Commercial terms changed for Bet Trade [Redmine: #61342]
		- 20160808@Bravo: #57972 - LA/ OWA - Change Commercial Terms for BetTrade
		- 20160808@Jim:  LRF - Integrate Allbet [Redmine: #61066]
		- 20161115@Jim: LRF - Integrate new product Fishing World [RedmineID : #66737]
		- 20170221@bruce: support NG2 [#70050]
		- 20170327@Harper: #73110 - Integrate new product Cashout
		- 20170712@Harper: #79310 - Integrate new product Betradar Virtual Sport
		- 20171006@Harper: #79311 - Support Macau products
		- 20171127@Sophia: #87257 - Support New range bettype for RNG casino
		- 20171214@Sophia: #86640 - Add Exchange Citi Product
		- 20180604@Bruce: #96383 - New Bettype range for VS2
		- 20180420@Bruce: LA - Implement sum job for Pragmatic [RedmineId #93958]
		- 20180910@Bruce: LA - Implement sum job for Poker & bullfighting [RedmineId #98487]
		- 20181204@Bruce: Implement E-sport 2  [RedmineId #105891]
		- 20181204@Bruce: Implement Happy 5,Reserved range for esport2 [RedmineId #105723]
		- 20190307@Parsons: Implement BetBuilder [Redmine: #108995]
		- 20190603@Parsons: Extend Lottery's bet types range [Redmine: #114568]
		- 20190712@Mason: Add Card Club Win Loss report [RedmineId #116096]
		- 20191024@Parsons: Non-peak hour promotion [#119538]    
		- 20191223@Parsons: Integrate Spadegaming [#123959]    
		- 20200302@Parsons: Integrate Virtual Games [#125222]
		- 20200326@Parsons: Integrate Sexy Gaming [#130948]
		- 20200411@Parsons: Integrate Tables Games [#131166]
		- 20200415@Pasons: Integrate SA Gaming [#129276]  

	Param's Explanation:

*/

BEGIN
	DECLARE @ProductList TABLE (ProductCode VARCHAR(10))

	INSERT INTO @ProductList (ProductCode)
	SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductCodes, ',')

    IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'SB')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 0
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid < 31
		  OR typeid BETWEEN 121 AND 999
		  OR typeid BETWEEN 9001 AND 9399
		  OR typeid BETWEEN 1301 AND 1399
		  OR typeid = 38 -- BetBuilder
		)
		AND typeid NOT IN (901, 902, 903,904, 911, 912, 913, 914) -- Bettrade bettypes 
		AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BA')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 3
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid < 31
			  OR typeid BETWEEN 121 AND 999
			  OR typeid BETWEEN 9001 AND 9399
			  OR typeid BETWEEN 1301 AND 1399
			  OR typeid = 38 -- BetBuilder
			 )
		  AND typeid NOT IN (901, 902, 903,904, 911, 912, 913, 914) -- Bettrade bettypes
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'RB')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 1
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid IN (31, 32, 33, 41, 42, 43)
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'NG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 2
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid BETWEEN 81 AND 120 OR typeid BETWEEN 8101 AND 8120)
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'LC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 4
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1101 AND 1199
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VS')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 5
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1201 AND 1299
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CS')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 6
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE (typeid IN (71, 72) 
			  OR typeid BETWEEN 2101 AND 2399
			  OR typeid BETWEEN 2901 AND 2999
			  )
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 7
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 73
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'KN')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 8
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1501 AND 1599
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'MGCLC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 14
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 2001 AND 2007
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
    
    IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'MGCRNG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 17
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 2008 AND 2009
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'GD')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 11
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1701 AND 1799
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BT')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 13
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 901 AND 904
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'AGC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 10
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1801 AND 1899
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CF')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 19
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 1003
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CB')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 15
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 18000 AND 18006
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VB')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 22
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 4001 AND 4100
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'PP')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 32
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 4101 AND 4300
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'AB')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 21
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 2401 AND 2499
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'FW')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 24
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid  BETWEEN 1011 AND 1020
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'NG2')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 23
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid  BETWEEN 2501 AND 2699
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CO')
	BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 25
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 911 AND 914
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VS2')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 27
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 2700 AND 2829
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'LT')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 28
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1021 AND 1049
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 12
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 1900
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BX')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 31
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 8000 AND 8099
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'BF')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 30
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid IN (1004)
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'PG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 33
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1401 AND 1499
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'CC')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 34
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 1901 AND 1999
		  AND (@Bettype = 0 OR typeid = @Bettype)
    END
	
	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'SPR')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 37
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid = 17000
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'SG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 36
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 4301 AND 4600
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'VRG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 38
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 4601 AND 4900
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'SXG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 45
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 3101 AND 3199
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'TG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 40
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 4901 AND 5000
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	IF EXISTS(SELECT 1 FROM @ProductList WHERE ProductCode LIKE 'SAG')
    BEGIN
	   INSERT INTO @tbBettypeProduct
	   SELECT typeid, 39
	   FROM bodb02.dbo.bettype WITH (NOLOCK)
	   WHERE typeid BETWEEN 3001 AND 3099
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	RETURN
END
GO