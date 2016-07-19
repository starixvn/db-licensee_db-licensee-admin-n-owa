USE [bodb_licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Inv_HostingFeeSettlement]
	@PayerId	INT,
	@FromDate	DATETIME,
	@ToDate	DATETIME
AS
/*	Task : Get hostingfees settlement
	DB: DB052.bodb_Licensee

	Revisions:
		+ 20160718@Bruce: Create

	Example:
		USE bodb_licensee
		EXEC [LA_Inv_HostingFeeSettlement] 14, '20160101', '20160630'
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(5))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE bodb_Licensee.dbo.LA_SelBaseCurrency
	
	DECLARE @ChargeRates TABLE (
		PartyName		NVARCHAR(100),
		FirstBilling	DATETIME,
		BasisOfBilling	NVARCHAR(4000),
		VCMFrom			INT,
		VCMTo			INT,
		Amount			MONEY,
		CurrencyName	VARCHAR(5)
	)

	INSERT INTO @ChargeRates
	SELECT
		p.PartyName,
		s.FirstBilling,
		s.BasisOfBilling,
		d.VCMFrom,
		d.VCMTo,
		d.Amount,
		bct.CurrencyName
	FROM dbo.LA_HostingFeesSetting s WITH(NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = s.FromParty
		INNER JOIN dbo.LA_HostingFeesDetail d WITH(NOLOCK) ON d.HostingFeesId = s.HostingFeesId
		INNER JOIN	@BaseCurrencyTable bct ON d.BaseCurrencyId = bct.CurrencyId
	WHERE s.FromParty = @PayerId
		AND @ToDate BETWEEN s.FromDate AND s.ToDate
		AND s.SettingType = 1
	ORDER BY d.VCMFrom

	DECLARE @FirstBilling DATETIME = (SELECT TOP 1 FirstBilling FROM @ChargeRates)
	IF ISNULL(@FirstBilling,@FromDate) > @FromDate
	BEGIN
		SET @FromDate = @FirstBilling
	END

	-- settlement report
	;WITH Settlement AS(
		SELECT
			i.FromDate,
			i.ToDate,
			i.MaxPCU,
			i.RateAmount,
			bct.CurrencyName,
			i.Amount,
			CASE WHEN i.IsWaived = 1 THEN 'waived' ELSE '' END WaivedStatus,
			ROW_NUMBER() OVER (PARTITION BY i.FromDate ORDER BY i.InvoiceHeaderId DESC) AS RowIndex
		FROM dbo.LA_InvoiceHeader i WITH(NOLOCK)
			INNER JOIN	@BaseCurrencyTable bct ON i.CurrencyId = bct.CurrencyId
			INNER JOIN dbo.LA_InvoiceType it WITH(NOLOCK) ON it.InvTypeId = i.InvoiceType
		WHERE i.PartyId = @PayerId 
			AND i.HasDeleted = 0
			AND it.InvTypeName LIKE '%Hosting Fees%'
			AND i.FromDate BETWEEN @FromDate AND @ToDate
	)
	SELECT * FROM Settlement WHERE RowIndex = 1

	SELECT * FROM @ChargeRates
END

GO
GRANT EXECUTE ON [dbo].[LA_Inv_HostingFeeSettlement] TO bodbAdminNet