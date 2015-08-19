USE bodb_licensee
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceDetailInfoGet] 
	 @PartyId			INT,  
	 @FromDate			DATETIME,
	 @ToDate			DATETIME,  
	 @ProductCode		VARCHAR(200),
	 @CurrencyId		INT			= 0	,
	 @BaseCurrencyName VARCHAR(20)	= 'GBP'
AS
/*	Header:
	Created: 2015.08.07 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_licensee
   
	Revisions: 
		+ 2015.08.07: Invoice Detail Info - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @FromDate DATETIME,
		@ToDate DATETIME,
		@PartyId INT,
		@ProductCode VARCHAR(100)
		
	SET @FromDate = '2015-07-1'
	SET @ToDate = '2015-07-31'
	SET @PartyId=17
	SET @ProductCode='SB,BA,RB,NG,LC,VS,CS,BG,KN,PTCS,AGC,GD,VG'	
	
	EXEC [LA_Inv_InvoiceDetailInfoGet] @PartyId, @FromDate, @ToDate, @ProductCode
*/
BEGIN
	SET NOCOUNT ON
	
	-- Region: Get party charge rate info	
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME,
		RowNumber	INT)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, RowNumber)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate, ROW_NUMBER() OVER (ORDER BY ProductId, Todate)
		FROM	dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)		
	
	-- End Region
	
	-- Region: Product Code
	DECLARE @Products AS TABLE(
			ProductId	INT,
			ProductCode VARCHAR(10),
			ProductName VARCHAR(200)
	)
	INSERT INTO @Products(ProductId,ProductCode, ProductName)
	SELECT DISTINCT
			i.ProductId,
			CASE 
				WHEN i.ProductId = 0 THEN 'SB' 
				ELSE p.ProductPrefix
			END AS ProductCode,
			CASE 
				WHEN i.ProductId = 0 THEN 'Sportsbook' 
				ELSE p.ProductName
			END AS ProductName			
	FROM	@PartyChargeInfo i  
			LEFT JOIN dbo.Product3rd p ON i.ProductId = p.Productid	
	-- End Region
	
	-- Region: Call data from sp Settlement.
	CREATE	TABLE #tmpResult(
			GroupId				INT,
			FromDate			DATETIME,
			ToDate				DATETIME,
			ProductCode			VARCHAR(10),
			ProductName			VARCHAR(200),
			Game				VARCHAR(100),
			WinLostDate			DATETIME,
			Currency			INT,
			CurrencyName		NVARCHAR(20),
			Betcount			INT,
			Turnover			MONEY,
			MemberWinLoss		MONEY,
			MemberComm			MONEY,
			LicenseeWL			MONEY,
			LicenseeComm		MONEY,	
			Company				MONEY,
			TurnoverBase		MONEY,	
			MemberWinLossBase	MONEY,
			LicenseeWLBase		MONEY,
			CompanyBaseCurrency	MONEY
	)
	
	DECLARE @Index INT = 1
	WHILE (SELECT COUNT(1) FROM @PartyChargeInfo pci WHERE pci.RowNumber = @Index) > 0
	BEGIN
		DECLARE @TempProductCode VARCHAR(10), @ProductName VARCHAR(200), @TempFromDate DATETIME, @TempToDate DATETIME
		SELECT	TOP 1 @TempProductCode = p.ProductCode, @ProductName = p.ProductName, @TempFromDate = pci.FromDate, @TempToDate = pci.ToDate
		FROM	@PartyChargeInfo pci INNER JOIN @Products p ON pci.ProductID = p.ProductId
		WHERE	pci.RowNumber = @Index
		
		BEGIN TRY
			INSERT INTO #tmpResult(Game,WinLostDate,Currency,CurrencyName,Betcount,Turnover,MemberWinLoss,MemberComm,LicenseeWL,LicenseeComm,Company,TurnoverBase,MemberWinLossBase,LicenseeWLBase,CompanyBaseCurrency)
			EXECUTE bodb02.dbo.LA_Rpt_LicenseeSettlement @PartyId, @TempFromDate, @TempToDate, @TempProductCode, 0, @BaseCurrencyName	
		END TRY
		BEGIN CATCH
		END CATCH
		
		UPDATE	#tmpResult
		SET		GroupId		= @Index,
				FromDate	= @TempFromDate,
				ToDate		= @TempToDate,
				ProductCode = @TempProductCode,
				ProductName = @ProductName
		WHERE	GroupId IS NULL    
				
		SET @Index = @Index + 1
	END	
	
	SELECT	r.GroupId, 
			r.FromDate,
			r.ToDate,
			r.ProductCode,
			r.ProductName,
			r.Game, 
			r.WinLostDate, 
			r.Currency, 
			r.CurrencyName, 
			r.Betcount, 
			r.Turnover,
			r.MemberWinLoss,
			r.MemberComm,
			r.LicenseeWL,
			r.LicenseeComm,
			r.Company,
			r.TurnoverBase,
			r.MemberWinLossBase,
			r.LicenseeWLBase,
			r.CompanyBaseCurrency
	FROM	#tmpResult r
	
	-- End region
	
	DROP TABLE #tmpResult
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceDetailInfoGet] TO bodbAdminNet