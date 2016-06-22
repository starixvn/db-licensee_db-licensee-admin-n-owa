USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesChargeRateSel]
	 @PayerId		INT = 0,
	 @HostingFeesId	INT	= 0	
AS
/*  
	 Created: 20160615@Bravo
	 Task : Get all hosting fees charge rate settings
	 DB: DB052.bodb_Licensee  
   
	 Revisions:
	 Params:
		
	 Example:
		EXEC dbo.LA_HostingFeesSel 0
*/
BEGIN	
	SET NOCOUNT ON
	DECLARE @Currency TABLE(
		Id INT, Name VARCHAR(10)
	)

	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)
	DECLARE @LastDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)

	INSERT INTO @Currency
	SELECT ExchangeID, Code
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FirstDate, @LastDate, 'EUR')

	SELECT s.FromParty AS PayerId,
		p.PartyName AS PayerName,
		s.FirstBilling,
		s.FromDate,
		s.ToDate,		
		pr.ProductName AS BasedMinimunFeesName,
		s.HostingFeesId, 
		f.HostingFeesName,
		t.HostingFeesTypeName,
		c.Name AS Exchange
	FROM dbo.LA_HostingFeesSetting s 
		INNER JOIN dbo.OAS_Party p ON s.FromParty = p.PartyID
		INNER JOIN dbo.LA_HostingFees f ON s.HostingFeesId = f.HostingFeesId
		INNER JOIN dbo.LA_HostingFeesTypes t ON f.HostingFeesTypeId = t.HostingFeesTypeId
		INNER JOIN @Currency c ON s.BaseCurrencyId = c.Id
		LEFT JOIN (SELECT ProductID, ProductName FROM dbo.LA_f_Products3rd('') )pr ON s.BasedMinimunFees = pr.ProductID
	WHERE (@PayerId = 0 OR s.FromParty = @PayerId)
		AND (@HostingFeesId = 0 OR s.HostingFeesId = @HostingFeesId)
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesChargeRateSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesChargeRateSel] TO bodbAdminNet 

