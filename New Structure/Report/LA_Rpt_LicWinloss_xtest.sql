USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicWinloss_xtest]    Script Date: 01/12/2014 14:34:14 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicWinloss_xtest] 
	  @PartyIDs				VARCHAR(1000)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)
	, @SportType			INT				= 0
	, @Bettype				INT				= 0
	, @ReportBy				TINYINT			= 1
	, @DrawFilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'

WITH RECOMPILE
AS
/*   Created:  Florent.Nguyen
	Date: 20140827
		Original: OA_Rpt_LicWinloss_Summary
	Task : LA Get Party Winloss
		DB: DB052.bodb02  
   
		Revisions:  
		- 20141021@Florent: get data from credit's licensee
		- 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
		- 20141226@Florent: Fix hafl-won, hafl-lose on Racing
		- 20150330@Florent: Fix case FDL licensee duplicate data
		- 20150703@Florent: add GBP
		- 20151013@Forrest: Up to date new flow
	Param's Explanation:  
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0- All Currencies
		+ @ReportBy: 1-Daily; 2-Monthly;  
		+ @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @excludeTest: add/remove currency UUS
		+ @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
		+@SportType	:
				0  : selected all sporttype 
		+@Bettype : 
			0: selected all bettype
*/
BEGIN
	SET NOCOUNT ON
	SET @ReportBy = 2 -- only allow monthly
	
	CREATE TABLE #Temp (PartyID INT, ProductID INT, ReportDate DATE, CurrencyID INT, TurnOver MONEY, Winlost MONEY, LicenseeWL MONEY, WinlossRB MONEY, 
						AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Playercomm MONEY, Betcount BIGINT)
	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)  
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT, Rate MONEY, Fromdate DATE, Todate DATE)
	
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @excludeTest)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate AS Rate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END
	
	SELECT * FROM @ChargeInfo
	SELECT * FROM #Temp
	SELECT * FROM #Exchange
	
	DELETE #Exchange
	DELETE #Temp
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicWinloss_xtest] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicWinloss_xtest] TO bodbAdminNet 
