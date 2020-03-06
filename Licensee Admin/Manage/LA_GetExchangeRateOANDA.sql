/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_GetExchangeRateOANDA]
	@Fromdate	DATETIME=NULL,
	@ToDate		DATETIME=NULL 
AS

/*
	Created by: 20180518@Scofield
	Task: OANDA Exchange Rate Report
	DB: DBLIC.bodb_Licensee
	
	Revisions:
		- 20180518@Scofield: create [#94950]
		- 20200228@Parsons: Support-HID-currency [#128856]
*/  
	SET NOCOUNT ON 
 
	BEGIN 
		IF @Fromdate IS NULL
			SET @Fromdate = CONVERT(VARCHAR(10), CURRENT_TIMESTAMP, 120)
		IF @Todate IS NULL
			SET @ToDate = CONVERT(VARCHAR(10), CURRENT_TIMESTAMP, 120)

		SELECT 
			edo.ExchangeDate,
			CASE 
				WHEN edo.Code='VND' THEN 'INH' 
				WHEN edo.Code='MMK' THEN 'MKK' 
				WHEN edo.ExchangeId = 75 THEN 'PTU'
				WHEN edo.ExchangeId = 76 THEN 'PS'
				WHEN edo.ExchangeId = 77 THEN 'PTH'
				WHEN edo.ExchangeId = 92 THEN 'HID'
				ELSE edo.Code 
			END CurrencyCode,
			edo.EUR,
			edo.USD,
			edo.MYR,
			edo.CNY,
			edo.IDR,
			edo.AUD,
			edo.CHF,
			edo.GBP,
			edo.SGD,
			edo.THB,
			edo.VND / 1000 AS 'INH',
			edo.KRW,
			edo.JPY,
			edo.HKD,
			edo.TWD,
			edo.PHP
		FROM bodb02.dbo.ExchangeDailyOanda edo (NOLOCK)
		WHERE 
			edo.ExchangeDate>=@fromdate AND edo.ExchangeDate<=@todate 
			AND edo.exchangeid in (select distinct currency   FROM  dbo.f_SelLicenseeCust(0) lc )
			AND exchangeid <> 20
			AND edo.ExchangeId NOT IN (43, 66) -- old THB and KeenOcean's HKD
		ORDER BY edo.ExchangeDate,edo.Code ASC 
	END
GO