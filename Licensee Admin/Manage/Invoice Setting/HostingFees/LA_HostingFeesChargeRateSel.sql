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
		20160705@Bruce: Update: get latest hosting fees setting of payer
	Params:

	Example:
		EXEC dbo.LA_HostingFeesChargeRateSel
*/
BEGIN	
	SET NOCOUNT ON

	DECLARE @ProductName VARCHAR(50) = 'Hosting'
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)
	DECLARE @LastDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, GETDATE()), 0)

	-- Waive settings
	BEGIN
		DECLARE @WaiveSettings TABLE (
			FromParty			INT,
			FromDate			DATETIME,
			ToDate				DATETIME,
			ProductName			VARCHAR(100),
			BasedMinimunFees	INT
		)

		;WITH ws AS (
			SELECT	FromParty,
					FromDate,
					ToDate,
					ProductName,
					BasedMinimunFees,
					HostingFeesId,
					ROW_NUMBER() OVER (PARTITION BY FromParty ORDER BY FromDate DESC) RowNumber
			FROM dbo.LA_HostingFeesSetting WITH(NOLOCK)
			WHERE SettingType = 2
				AND ProductName = @ProductName
				AND (@PayerId = 0 OR @PayerId = FromParty)
		)
		INSERT INTO @WaiveSettings
		SELECT FromParty, FromDate, ToDate, ProductName, BasedMinimunFees
		FROM ws WHERE RowNumber = 1 AND (@HostingFeesId = 0 OR HostingFeesId = @HostingFeesId)
	END

	-- Hosting fees Settings
	BEGIN
		DECLARE @HostingSettings TABLE (
			FromParty			INT,
			ProductName			VARCHAR(100),
			FirstBilling		DATETIME,
			BasisOfBilling		NVARCHAR(2000),
			HostingFeesId		INT,
			BaseCurrencyId		INT
		)

		;WITH hs AS (
			SELECT	FromParty,
					ProductName,
					FirstBilling,
					BasisOfBilling,
					HostingFeesId,
					BaseCurrencyId,
					ROW_NUMBER() OVER (PARTITION BY FromParty ORDER BY FromDate DESC) RowNumber
			FROM dbo.LA_HostingFeesSetting WITH(NOLOCK)
			WHERE SettingType = 1
				AND ProductName = @ProductName
				AND (@PayerId = 0 OR @PayerId = FromParty)
		)
		INSERT INTO @HostingSettings
		SELECT FromParty, ProductName, FirstBilling, BasisOfBilling, HostingFeesId,BaseCurrencyId
		FROM hs WHERE RowNumber = 1 AND (@HostingFeesId = 0 OR HostingFeesId = @HostingFeesId)
	END

	-- Hosting fees charge rate info
	BEGIN
		DECLARE @ChargeRateInfo TABLE (
			HostingFeesId		INT,
			HostingFeesText		VARCHAR(4000)
		)

		INSERT INTO @ChargeRateInfo
		SELECT DISTINCT d1.HostingFeesId, STUFF((
					SELECT ',', CAST(CONVERT(DOUBLE PRECISION,Amount) AS VARCHAR(10))
					FROM dbo.LA_HostingFeesDetail AS d2 WITH (NOLOCK)
					WHERE d2.HostingFeesId = d1.HostingFeesId
					FOR XML PATH(''))
				, 1, 1, '')
		FROM LA_HostingFeesDetail AS d1 WITH (NOLOCK)
		WHERE d1.HostingFeesId IN (SELECT HostingFeesId FROM @HostingSettings)
	END

	SELECT
		hs.FromParty AS PayerId,
		CASE
			WHEN ISNULL(pd.BrandName, '') != '' THEN pd.BrandName
			ELSE p.PartyName
		END AS PayerName,
		hs.FirstBilling,
		ws.FromDate,
		ws.ToDate,
		pr.ProductName AS BasedMinimunFeesName,
		f.HostingFeesName,
		t.HostingFeesTypeName,
		c.Code AS Exchange,
		hs.ProductName,
		r.HostingFeesText
	FROM @HostingSettings hs
		LEFT JOIN @WaiveSettings ws ON hs.FromParty = ws.FromParty
		LEFT JOIN dbo.LA_f_Products3rd('') pr ON ws.BasedMinimunFees = pr.ProductID
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON hs.FromParty = p.PartyID
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyID = pd.PartyID
		INNER JOIN dbo.LA_HostingFees f ON hs.HostingFeesId = f.HostingFeesId
		INNER JOIN dbo.LA_HostingFeesTypes t ON f.HostingFeesTypeId = t.HostingFeesTypeId
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FirstDate, @LastDate, 'EUR') c ON hs.BaseCurrencyId = c.ExchangeID
		INNER JOIN @ChargeRateInfo r ON hs.HostingFeesId = r.HostingFeesId
	ORDER BY hs.FromParty

END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_HostingFeesChargeRateSel] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_HostingFeesChargeRateSel] TO bodbAdminNet
