/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_DiscountByGrossWin_RateByCurrencySel]
	@CurrencySettingsData		VARCHAR(MAX) = '',
	@ChargeRateAfterDiscount	MONEY,
	@DiscountGroupId			SMALLINT = NULL

AS

/*  
	 Created: 20230111@Danny
	 DB: DBLIC.bodb_licensee
	 Task: Manage Discount Group - Discount By Gross Win - PopUp Discount rate information
	 
	 
	 Revisions:
		- 20221201@Danny: Initialize SP [RedmineID: #169160]
		- 20230801@Danny: Incorporate USDT2 currency [RedmineID: #191165]
		- 20231002@Danny: Support Jollysport licensees [#FeatureID 193214]
	 Params:
	 @CurrencySettingsData = '<Root>
								<CurrencySetting>
									<PartyId>1</PartyId>
									<CurrencyId>2</CurrencyId>
								</CurrencySetting>
								<CurrencySetting>
									<PartyId>3</PartyId>
									<CurrencyId>4</CurrencyId>			
								</CurrencySetting>
							 </Root>'


*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CurrencyXML XML = CONVERT(XML, @CurrencySettingsData)
	DECLARE @CurrencyList TABLE (PartyId INT, CurrencyId INT, CurrencyCode VARCHAR(65), CurrencyName VARCHAR(50))

	INSERT INTO @CurrencyList (PartyId, CurrencyId)
	SELECT x.PartyId, y.CurrencyId
	FROM 
	(
		SELECT t.c.value('(PartyId/text())[1]', 'INT') AS PartyId
			,t.c.value('(CurrencyId/text())[1]', 'VARCHAR(4000)') AS CurrencyId
		FROM @CurrencyXML.nodes('Root/CurrencySetting') AS t(c)
		
	) x
	CROSS APPLY 
	(
		SELECT CAST(value AS INT) AS CurrencyId FROM STRING_SPLIT(x.CurrencyId,',')
	) y
	OPTION (OPTIMIZE FOR (@CurrencyXML = NULL))

	UPDATE c
	SET c.CurrencyCode = CASE WHEN c.CurrencyId = 142 THEN 'USDT' WHEN c.CurrencyId IN (96,202, 206, 208, 209) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END,
		c.CurrencyName = e.currency
	FROM @CurrencyList c 
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON c.CurrencyId = e.ExchangeId

	UPDATE c1
	SET c1.CurrencyCode = c1.CurrencyCode + ' (' + c1.CurrencyName + ')'
	FROM @CurrencyList c1
	INNER JOIN (
		SELECT PartyId, CurrencyCode
	    FROM @CurrencyList
	    GROUP BY PartyId, CurrencyCode
	    HAVING COUNT(1) > 1
	) c2 ON c1.PartyId = c2.PartyId AND c1.CurrencyCode = c2.CurrencyCode

	IF (@DiscountGroupId IS NULL OR  @DiscountGroupId = 0)-- Get current chargeRate
	BEGIN
		; WITH t AS
		(
		SELECT  op.PartyName, 
				c.CurrencyCode AS CurrencyName,  
				e.ExchangeID AS CurrencyID,
				CASE WHEN lc.Rate IS NOT NULL THEN lc.Rate ELSE oc.Rate END ChargeRateByCurrency
				,@ChargeRateAfterDiscount AS ChargeRateAfterDiscount
				,op.PartyID
				,CASE WHEN lc.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate
		FROM	@CurrencyList c
		INNER JOIN OAS_Party op WITH(NOLOCK) ON c.PartyId = op.PartyID
		INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON c.CurrencyId = e.ExchangeId
		INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON oc.FromParty = c.PartyId AND oc.ProductID = 0 
		INNER JOIN LA_ChargeInfo_SystemMapping cs  WITH(NOLOCK) ON oc.ChargeID = cs.ChargeID
		LEFT JOIN LA_ChargeRateByCurrency  lc WITH(NOLOCK) ON oc.ChargeID = lc.ChargeID AND c.CurrencyId = lc.CurrencyID
		WHERE oc.FromDate <= GETDATE() AND oc.ToDate >= GETDATE() AND cs.SystemID = 2 AND oc.ChargeType = 1
		)
		SELECT	PartyID
				,PartyName
				,CurrencyID
				,CurrencyName
				,ChargeRateByCurrency
				,CASE WHEN ChargeRateAfterDiscount > ChargeRateByCurrency THEN ChargeRateByCurrency ELSE ChargeRateAfterDiscount END ChargeRateAfterDiscount
				,CASE WHEN ChargeRateByCurrency > ChargeRateAfterDiscount THEN ChargeRateByCurrency - ChargeRateAfterDiscount ELSE 0 END DiscountRate
				,isMasterRate
		FROM t
	END
	ELSE
	BEGIN
		-- Get Discount group Info
		DECLARE @D_FromDate DATE, @D_ToDate DATE
		SELECT  @D_FromDate = FromDate, @D_ToDate = ToDate
		FROM	LA_DiscountGroupHeader WITH(NOLOCK) WHERE DiscountGroupId = @DiscountGroupId

		; WITH t AS
		(
		SELECT  op.PartyName, 
				c.CurrencyCode AS CurrencyName,  
				e.ExchangeID AS CurrencyID,
				CASE WHEN lc.Rate IS NOT NULL THEN lc.Rate ELSE oc.Rate END ChargeRateByCurrency
				,@ChargeRateAfterDiscount AS ChargeRateAfterDiscount
				,op.PartyID
				,CASE WHEN lc.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate
		FROM	@CurrencyList c
		INNER JOIN OAS_Party op WITH(NOLOCK) ON c.PartyId = op.PartyID
		INNER JOIN bodb02.dbo.Exchange e WITH(NOLOCK) ON c.CurrencyId = e.ExchangeId
		INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON oc.FromParty = c.PartyId AND oc.ProductID = 0 
		INNER JOIN LA_ChargeInfo_SystemMapping cs  WITH(NOLOCK) ON oc.ChargeID = cs.ChargeID
		LEFT JOIN LA_ChargeRateByCurrency  lc WITH(NOLOCK) ON oc.ChargeID = lc.ChargeID AND c.CurrencyId = lc.CurrencyID
		WHERE	(	oc.FromDate BETWEEN @D_FromDate AND @D_ToDate 
					OR oc.ToDate BETWEEN @D_FromDate AND @D_ToDate 
					OR @D_FromDate BETWEEN oc.FromDate AND oc.ToDate
					OR @D_ToDate BETWEEN oc.FromDate AND oc.ToDate
				)
			AND cs.SystemID = 2 AND oc.ChargeType = 1
		)
		SELECT	DISTINCT
				PartyID
				,PartyName
				,CurrencyID
				,CurrencyName
				,ChargeRateByCurrency
				,CASE WHEN ChargeRateAfterDiscount > ChargeRateByCurrency THEN ChargeRateByCurrency ELSE ChargeRateAfterDiscount END ChargeRateAfterDiscount
				,CASE WHEN ChargeRateByCurrency > ChargeRateAfterDiscount THEN ChargeRateByCurrency - ChargeRateAfterDiscount ELSE 0 END DiscountRate
				,isMasterRate
		FROM t

	END

END
GO