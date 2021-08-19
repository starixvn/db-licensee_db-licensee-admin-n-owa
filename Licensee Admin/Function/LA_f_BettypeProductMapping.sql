/*<info serverAlias="DBLIC-bodb_Licensee,DBBAL-bodb_Licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER FUNCTION [dbo].[LA_f_BettypeProductMapping] (
	 @Bettype	 	INT = 0
	,@ProductCodes VARCHAR(1000)= ''	
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
		- 20200415@Parsons: Integrate SA Gaming [#129276]  
		- 20200418@Parsons: Integrate BBIN Live Casino [#132237]
		- 20200422@Parsons: Indo 4D Integration [#130910]
		- 20200424@Pasons: Integrate IBCBET Live Casino [#131165]
		- 20200423@Parsons: Integrate Saba-Club [#132730]
		- 20200610@Parsons: Implement RNG WAR and ION [#134452]
		- 20200717@Parsons: Extend bet type range for Lottery [#137840] 
		- 20200810@Parsons: Implement Saba Loyalty Program [#139167]  
		- 20200909@Parsons: Integrate PG Soft [#138983]  
		- 20200921@Parsons: Integrate Joker Games [#141421]  
		- 20201008@Parsons: Integrate WM Live Casino [#141357]  
		- 20201130@Parsons: Integrate Leap Gaming Virtual Sports [#145339]
		- 20201203@Parsons: Integrate Gold Diamond Gaming [#145340]
		- 20210104@Parsons: Integrate Big Gaming [#145342]
		- 20210104@Parsons: Integrate MaxGame [#147375]
		- 20210104@Parsons: Integrate Happy 5 Linked Games [#147544]
		- 20210203@Parsons: Integrate Saba Red Envelope [#149935]
		- 20210308@Parsons: Integrate Habanero  Product [#150636]
		- 20210308@Parsons: Integrate Sports Lottery Product [#150866]
		- 20210401@Parsons: Add new bet types All In One of Cricket [#150147]
		- 20210412@Sophia: Integrate PP Live Casino [Redmine: #150971]
		- 20210419@Danny: Integrate Creative Gaming [Redmine: #152139]
		- 20210412@Sophia: Change Range of AE Casino [Redmine :#152141]
		- 20210428@Danny: Integrate VGaming with dynamic code [Redmine: #154080]
		- 20210618@Sophia: Expand Range of Saba Promotion [Redmine: #155337]
		- 20210514@Danny: Get bettype from SportBettypeMatrix (All products) [Redmine: #155126]
		- 20210816@Sophia: add DBBAL [Redmine: #154300]

	Param's Explanation:

*/
BEGIN
	DECLARE @ProductList TABLE (ProductCode VARCHAR(10))

	IF @ProductCodes = ''
	BEGIN
		INSERT INTO @ProductList (ProductCode)
		SELECT d.ProductPrefix
		FROM bodb_licensee.dbo.Product3rd d WITH(NOLOCK) 
		WHERE EXISTS( SELECT 1 FROM  bodb02.dbo.Products p WITH (NOLOCK) WHERE p.ProductPrefix = d.ProductPrefix)

		INSERT INTO @ProductList VALUES ('SB')
		INSERT INTO @ProductList VALUES ('BT')
		INSERT INTO @ProductList VALUES ('BA')

	END
	ELSE
	BEGIN
		INSERT INTO @ProductList (ProductCode)
		SELECT DISTINCT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductCodes, ',')
	END

	--- Dynamic function
	DECLARE @mappingProductMatrix TABLE (ProductID INT, ProductID_3rd INT, ProductPrefix VARCHAR(10))

	INSERT INTO @mappingProductMatrix (ProductID, ProductID_3rd, ProductPrefix)
	SELECT p.ProductID , d.Productid as ProductID_3rd, p.ProductPrefix
	FROM  @ProductList t
	INNER JOIN bodb02.dbo.Products p WITH (NOLOCK) ON t.ProductCode = p.ProductPrefix
	INNER JOIN bodb_licensee.dbo.Product3rd d WITH(NOLOCK) ON p.ProductPrefix = d.ProductPrefix
    
	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode = 'SB')
	INSERT INTO @mappingProductMatrix (ProductID, ProductID_3rd, ProductPrefix) VALUES (1, 0, 'SB')
	
	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode = 'BA')
	INSERT INTO @mappingProductMatrix (ProductID, ProductID_3rd, ProductPrefix) VALUES (1, 3, 'BA')

	INSERT INTO  @tbBettypeProduct (Bettype, ProductID)
	SELECT DISTINCT  s.BetType, ma.ProductID_3rd
	FROM @mappingProductMatrix ma
	INNER JOIN bodb02.dbo.SportBettypeMatrix  s (NOLOCK) ON ma.ProductID = s.ProductID
	WHERE (
			s.BetType NOT IN (901, 902, 903,904) OR ma.ProductID <> 1
		 ) AND (@Bettype = 0 OR s.bettype = @Bettype) 
		 AND s.BetType NOT IN (1700, 1800, 18999) -- Bettype SUM of Product IN (10, 11)
		 AND s.isTest = 0

	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode = 'BT')
	BEGIN
	INSERT INTO @tbBettypeProduct (Bettype, ProductID)
	SELECT typeid, 13
	FROM bodb02.dbo.bettype WITH (NOLOCK)
	WHERE typeid BETWEEN 901 AND 904
		  AND (@Bettype = 0 OR typeid = @Bettype)
	END

	RETURN
END
GO