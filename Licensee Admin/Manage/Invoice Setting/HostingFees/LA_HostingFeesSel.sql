/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesSel]
	 @HostingFeesId	INT	= 0	
AS
/*  
	 Created: 20160615@Bravo
	 Task : Get all hosting fees settings
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]
		- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
		- 20230530@Danny: return HostingFeesDetailID [RedmineID: #175125]
	 Params:
		
	 Example:
		EXEC dbo.LA_HostingFeesSel 0
*/
BEGIN	
	SET NOCOUNT ON
	DECLARE @Currency TABLE(
		Id INT, Name VARCHAR(65)
	)

	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)

	INSERT INTO @Currency
	SELECT ExchangeID, Code
	FROM CustDB.dbo.LA_f_ExchangeDailySel(@FirstDate, @FirstDate, 'EUR')

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
			c1.Name AS RateCurrencyName,
			d.HostingFeesDetailId
	FROM dbo.LA_HostingFees f WITH(NOLOCK)
			INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON f.HostingFeesId = d.HostingFeesId
			INNER JOIN dbo.LA_HostingFeesTypes t WITH(NOLOCK) ON f.HostingFeesTypeId = t.HostingFeesTypeId
			INNER JOIN @Currency c ON f.BaseCurrencyId = c.Id
			INNER JOIN @Currency c1 ON d.BaseCurrencyId = c1.Id
	WHERE f.HostingFeesId = @HostingFeesId OR @HostingFeesId = 0
END
GO