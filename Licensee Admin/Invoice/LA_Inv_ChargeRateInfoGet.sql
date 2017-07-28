USE bodb_licensee
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_ChargeRateInfoGet] 
	 @PartyId			INT,  
	 @FromDate			DATETIME,
	 @ToDate			DATETIME,  
	 @ProductCodes		VARCHAR(200),
	 @CurrencyId		INT			= 0	,
	 @BaseCurrencyName VARCHAR(20)	= 'GBP'
AS
/*	Header:
	Created: 2015.08.07 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_licensee
   
	Revisions: 
		+ 2015.08.07: Charge rate Info - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @FromDate DATETIME,
		@ToDate DATETIME,
		@PartyId INT,
		@ProductCodes VARCHAR(100)
		
	SET @FromDate = '2015-07-1'
	SET @ToDate = '2015-07-31'
	SET @PartyId=17
	SET @ProductCodes='SB,BA,RB,NG,LC,VS,CS,BG,KN,PTCS,AGC,GD,VG'	
	
	EXEC [LA_Inv_ChargeRateInfoGet] @PartyId, @FromDate, @ToDate, @ProductCodes
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
		SELECT	PartyID, LicenseeID, ProductID, MAX(DI_Rate), Fromdate, Todate, ROW_NUMBER() OVER (ORDER BY ProductId, Todate)
		FROM	dbo.LA_f_ChargeInfo(@PartyId, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
		GROUP BY PartyID,LicenseeID,ProductID,Fromdate,Todate
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
	
	SELECT	c.*, p.ProductCode, p.ProductName
	FROM	@PartyChargeInfo c INNER JOIN @Products p ON c.ProductID = p.ProductId	
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_ChargeRateInfoGet] TO bodbAdminNet