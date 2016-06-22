USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesSel]
	 @HostingFeesId	INT	= 0	
AS
/*  
	 Created: 20160615@Bravo
	 Task : Get all hosting fees settings
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

	INSERT INTO @Currency
	SELECT ExchangeID, Code
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FirstDate, @FirstDate, 'EUR')

	SELECT	f.HostingFeesId, 
			f.HostingFeesName, 
			f.HostingFeesTypeId, 
			t.HostingFeesTypeName, 
			f.BaseCurrencyId AS ExchangeId, 
			c.Name AS ExchangeName,
			d.VCMFrom,
			d.VCMTo,
			d.Amount,
			d.BaseCurrencyId AS RateCurrencyId,
			c1.Name AS RateCurrencyName
	FROM dbo.LA_HostingFees f
			INNER JOIN dbo.LA_HostingFeesDetail d ON f.HostingFeesId = d.HostingFeesId
			INNER JOIN dbo.LA_HostingFeesTypes t ON f.HostingFeesTypeId = t.HostingFeesTypeId
			INNER JOIN @Currency c ON f.BaseCurrencyId = c.Id
			INNER JOIN @Currency c1 ON d.BaseCurrencyId = c1.Id
	WHERE f.HostingFeesId = @HostingFeesId OR @HostingFeesId = 0
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_HostingFeesSel] TO bodbAdminNet 

