USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceAmountGenerate]   Script Date: 07/20/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_AutoMail_LicenseeWinLossByProduct]	  
	@FromDate		DATETIME,
	@ToDate			DATETIME,	
	@CurrencyName	VARCHAR(10),	
	@ErrCode		INT				= 0		OUTPUT,
	@ErrMsg			NVARCHAR(1000)	= ''	OUTPUT
	
WITH RECOMPILE
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 2015.08.06: Invoice Amount - Generate
*/
/*	Example:
	USE bodb_Licensee
	DECLARE @FromDate		DATETIME		= '2015-7-1'
	DECLARE @ToDate			DATETIME		= '2015-7-31'
	DECLARe @CurrencyName	VARCHAR(10)		= 'GBP'
	DECLARE @ErrCode		INT				
	DECLARE @ErrMsg			NVARCHAR(1000)
		
	EXEC [LA_AutoMail_LicenseeWinLossByProduct] @FromDate, @ToDate, @CurrencyName, @ErrCode OUT, @ErrMsg OUT
	SELECT @ErrCode, @ErrMsg
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Get party charge rate info
	DECLARE @ProductCode VARCHAR(100)= 'SB,NG,RB,VS,LC,CS,KN,AGC,GD,VG'
	DECLARE @PartyIdString VARCHAR(2000)
	SELECT @PartyIdString = COALESCE(@PartyIdString + ', ', '') + CONVERT(VARCHAR(10), PartyId)
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
	WHERE PartyType = 1
	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
	-- End region
	
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange ( 
			ExchangeDate	DATE, 
			ExchangeID		INT, 
			CurrencyCode	VARCHAR(10), 
			Rate			FLOAT)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @CurrencyName)
	-- End region
	
	-- Region: Generate licensee name & group
	DECLARE @TempPartyList AS TABLE(
		PartyId		INT,
		PartyName	VARCHAR(200),
		BranchName	VARCHAR(200),
		ParentId	INT		
	)
	INSERT INTO @TempPartyList
	EXECUTE dbo.LA_PartyListSel
	
	CREATE TABLE #LicenseeAmount(		
		GroupName	VARCHAR(200),		
		PartyName	VARCHAR(200),
		BranchName	VARCHAR(200),		
		SB			MONEY,
		RB			MONEY,
		NG			MONEY,		
		BA			MONEY,
		LC			MONEY,
		VS			MONEY,
		CS			MONEY,
		KN			MONEY,
		AGC			MONEY,
		GD			MONEY,
		VG			MONEY
	)
	INSERT INTO #LicenseeAmount(GroupName,PartyName,BranchName)
	SELECT	p.PartyName, t.PartyName, t.BranchName
	FROM	@TempPartyList t INNER JOIN @TempPartyList p ON t.ParentId = p.PartyId
	WHERE	t.ParentId != 0
	
	SELECT * FROM #LicenseeAmount
	-- EndRegion
END

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceAmountGenerate] TO bodbAdminNet