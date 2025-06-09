/*<info serverAlias="DBCUST-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="1"></info>*/
CREATE PROCEDURE [dbo].[SH_ChargeRateSettingDel]
	@PayerID		   INT
	,@ChargeSettingXML NVARCHAR(MAX)
	,@UserID		   INT
	,@LoginIP		   VARCHAR(50) = ''
	,@ErrCode		   INT = 0 OUTPUT
	,@ErrMsg		   NVARCHAR(1000) = '' OUTPUT
AS
/*
	Created: 20250529@Eddie
	Task: Delete charge rate setting
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20250529@Eddie: Initialize SP [RedmineID: #223299]
		- 20250605@Danny: New format charge rate setting log [RedmineID: #226207]
								
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @StartRun DATETIME
		  , @Duration INT
		  , @LogSPData NVARCHAR(MAX)
		  , @LogSPDataOld NVARCHAR(MAX)
		  , @ActionID INT = 1202 -- DBLOG.bodb_CustomerLog.dbo.LA_LogAction.[ActionID]
		  , @SPName VARCHAR(50) = OBJECT_NAME(@@PROCID)
		  , @ChargeSettingsXML XML

	DECLARE @ChargeSetting AS TABLE 
	(
		Idx				INT IDENTITY(1,1)
	   ,ChargeID		INT
	   ,ProductId		INT
	   ,FirstBilling	DATE
	   ,BasisBilling	NVARCHAR(MAX)
	   ,BettypeRef		INT
	   ,Rate			MONEY
	   ,ChargeType		INT
	   ,ChargeTypeName	NVARCHAR(MAX)
	   ,FromDate		DATE
	   ,ToDate			DATE
	   ,IsChangedRate	BIT DEFAULT(1)
	   ,IsChangedDate	BIT DEFAULT(0)
	)

	SET @StartRun = GETDATE()

	IF ISNULL(@ChargeSettingXML, '') = '' RETURN

	SELECT @ChargeSettingsXML = CONVERT(XML, @ChargeSettingXML)
	
	INSERT INTO @ChargeSetting (ChargeID, ProductId, FirstBilling, BasisBilling, BettypeRef, Rate, ChargeType, ChargeTypeName, FromDate, ToDate)
	SELECT t.c.value('(ChargeId/text())[1]', 'INT') AS ChargeID
		  ,t.c.value('(ProductId/text())[1]', 'INT') AS ProductId
		  ,t.c.value('(FirstBilling/text())[1]', 'DATE') AS FirstBilling
		  ,t.c.value('(BasisBilling/text())[1]', 'NVARCHAR(MAX)') AS BasisBilling
		  ,t.c.value('(BettypeRef/text())[1]', 'INT') AS BettypeRef
		  ,t.c.value('(Rate/text())[1]', 'MONEY') AS Rate
		  ,t.c.value('(ChargeType/text())[1]', 'INT') AS ChargeType
		  ,t.c.value('(ChargeTypeName/text())[1]', 'NVARCHAR(MAX)') AS ChargeTypeName
		  ,t.c.value('(FromDate/text())[1]', 'DATE') AS FromDate
		  ,t.c.value('(ToDate/text())[1]', 'DATE') AS ToDate
	FROM @ChargeSettingsXML.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingsXML = NULL))
	
	DELETE @ChargeSetting WHERE ChargeID >= 0
	
	UPDATE @ChargeSetting
	SET ChargeID = ABS(ChargeID)
	WHERE ChargeID < 0

	-- Data for log
	;WITH t AS
	(
		SELECT op.PartyName
			  ,od.BrandName
			  ,CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END AS Product
			  ,FORMAT (oc.FromDate,'MMM dd, yyyy') AS FromDate
			  ,FORMAT (oc.ToDate,'MMM dd, yyyy') AS ToDate
			  ,FORMAT (oc.FirstOfBilling,'MMM dd, yyyy') AS FirstOfBilling
			  ,oc.BasisOfBilling
			  ,CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END AS Rate
			  ,CASE WHEN lcr.Rate IS NOT NULL THEN STRING_AGG(x.Code ,', ') ELSE '' END Currs
			  ,CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END AS isMasterRate
			  ,oc.ChargeID AS FakeID
			  ,z.ChargeTypeName
		FROM dbo.OAS_Party op WITH (NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail od WITH (NOLOCK) ON op.PartyID = od.PartyID
		INNER JOIN dbo.Licensees l WITH (NOLOCK) ON op.OldRefID = l.LicenseeID
		INNER JOIN dbo.OAS_ChargeInfo oc WITH (NOLOCK) ON op.PartyID = oc.FromParty
		CROSS APPLY (
			SELECT  e.ExchangeId AS Currency, e.Code + ' (' + e.currency + ')' Code
			FROM CustDB.dbo.exchange e with(nolock) 
			WHERE  e.ExchangeId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
		) x
		INNER JOIN @ChargeSetting z ON z.ChargeID = oc.ChargeID
		LEFT JOIN dbo.LA_ChargeRateByCurrency lcr WITH (NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
		LEFT JOIN dbo.Product3rd p3 WITH (NOLOCK) ON oc.ProductID = p3.Productid
		WHERE op.PartyID = @PayerID
		GROUP BY op.PartyName
				,od.BrandName
				,CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END
				,FORMAT(oc.FromDate,'MMM dd, yyyy')
				,FORMAT(oc.ToDate,'MMM dd, yyyy')
				,FORMAT(oc.FirstOfBilling,'MMM dd, yyyy')
				,oc.BasisOfBilling
				,CASE WHEN oc.ProductID = 3 THEN '0.25 %' ELSE (CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + ' %') END
				,CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END
				,oc.ChargeID
				,z.ChargeTypeName
				,lcr.Rate
	), t1 AS
	(
		SELECT t.FakeID, t.PartyName, t.BrandName, t.Product, t.FromDate, t.ToDate, t.FirstOfBilling, t.BasisOfBilling, t.ChargeTypeName, STRING_AGG(cr.r, CHAR(13)) AS r
		FROM t
		CROSS APPLY (
				SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others - ' 
							WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All - ' 
							ELSE '('+ t.Currs + ') - ' END + Rate AS r
		) cr
		GROUP BY t.FakeID, t.PartyName, t.BrandName, t.Product, t.FromDate, t.ToDate, t.FirstOfBilling, t.BasisOfBilling, t.ChargeTypeName
	)
	SELECT @LogSPDataOld = 
	(
		SELECT t.PartyName AS 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
		FROM t1 AS t
		CROSS APPLY
		(
			SELECT
			(
				SELECT u.FakeID, u.Product AS p, u.FromDate AS fd, u.ToDate AS td, u.FirstOfBilling AS fb, u.BasisOfBilling AS bb, u.r, u.ChargeTypeName AS t
				FROM t1 AS u
				WHERE u.PartyName = t.PartyName
				  AND u.BrandName = t.BrandName
				FOR JSON PATH
			) crs
		) crs
		GROUP BY t.PartyName, t.BrandName, crs.crs
		FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
	)

	BEGIN TRY

		DELETE ct WITH (ROWLOCK, UPDLOCK)
		FROM dbo.OAS_ChargeInfo AS ct
		WHERE ChargeID IN (SELECT ChargeID FROM @ChargeSetting)
		
		DELETE ct WITH (ROWLOCK, UPDLOCK)
		FROM dbo.LA_ChargeInfo_SystemMapping AS ct
		WHERE ChargeID IN (SELECT ChargeID FROM @ChargeSetting)

	END TRY
	BEGIN CATCH

		SELECT @ErrCode = 721, @ErrMsg = 'Delete failed. Please try again.'
		RETURN

	END CATCH

	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, GETDATE())

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			 = @UserID
		,@IP			 = @LoginIP
		,@SPName		 = @SPName
		,@CustId		 = @PayerID
		,@Duration		 = @Duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue  = @LogSPDataOld
		,@ActionID		 = @ActionID
END
GO