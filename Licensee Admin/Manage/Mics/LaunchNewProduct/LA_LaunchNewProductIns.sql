/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_LaunchNewProductIns]
	@ChargeSettingsXML	NVARCHAR(MAX)
	,@ProductCode		VARCHAR(10)
	,@LaunchDate	    DATE
	,@UserID			INT
	,@LoginIP			VARCHAR (50) = ''
	,@ErrCode			INT = 0 OUTPUT
	,@ErrMsg			NVARCHAR(1000) = '' OUTPUT
AS
/*
	Created: 20220919@Malcolm
	Task : Launch new licensee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20220919@Malcolm: Launch new Product [RedmineID: #175860]
		- 20221205@Danny: Remove Hx9candy From Crypto Licensee List [RedmineID: #181279]
		- 20230310@Danny: Insert new log with more information [#FeatureID 175125]
		
	Param's Explannation: 
		+ @ChargeSettingsXML: '<ChargeSettings>
								  <ChargeSetting>
									<PartyId>100</PartyId>
									<Rate>1</Rate>
									<BasisBilling>1</BasisBilling>
									<FromDate>2022-09-01</FromDate>
									<ToDate>2022-09-10</ToDate>				
								  </ChargeSetting>
								</ChargeSettings>'

*/
BEGIN
	SET NOCOUNT ON
	DECLARE @logChargeRateOld NVARCHAR(MAX), @logChargeRate NVARCHAR(MAX), @logChargeRateActionID INT = 1200 -- Add new chargerate
	DECLARE @logBillerOld NVARCHAR(MAX), @logBiller NVARCHAR(MAX), @logBillerActionID INT = 1003 -- Edit Biller
	DECLARE @StartRun DATETIME = CURRENT_TIMESTAMP, @EndRun DATETIME, @Duration	INT = 0, @Doing NVARCHAR(MAX)

	DECLARE @ChargeSettingXML XML, @ProductId INT, @Product3rdId TINYINT, @LicenseeId INT, @BillerId INT, @PartyId INT, @GroupName VARCHAR(50), @GroupId INT, @FromDate DATETIME, @ToDate DATETIME
			,@SiteName VARCHAR(20) = '', @InputPT VARCHAR(MAX) = '', @Rate MONEY, @UserName VARCHAR(50) = '', @PartyName VARCHAR(50), @PreLaunchDate DATETIME, @ChargeID INT

	DECLARE @Tmp TABLE (InvSettingId INT)

	SELECT @UserName = Username FROM dbo.LA_User WITH(NOLOCK) WHERE UserID = @UserID

	SELECT @ChargeSettingXML = CONVERT(XML, @ChargeSettingsXML)

	SELECT @Product3rdId = ProductId
	FROM dbo.LA_f_GroupProduct('',NULL,NULL) p
	WHERE p.ProductId = p.GroupProductId AND p.GroupProductCode = @ProductCode
	
	DECLARE @ErrorMessage TABLE (PartyId INT, PartyName VARCHAR(50), ErrCode INT, ErrMsg NVARCHAR(MAX))

	CREATE TABLE #ChargeSetting 
	(
		ID				INT IDENTITY(1, 1)
		,PartyId		INT
		,PartyName		VARCHAR(50)
		,Rate			MONEY
		,ChargeType		TINYINT
		,FromDate		DATETIME
		,ToDate			DATETIME
		,BasisBilling	NVARCHAR(4000)
		,BaseCurrencyId	INT
		,GroupId		INT
		,GroupName		VARCHAR(50)
		,BillerId		INT
		,LicenseeId		INT
	)

	INSERT INTO #ChargeSetting (PartyId, Rate, FromDate, ToDate, BasisBilling, ChargeType)
	SELECT		
			t.c.value('(PartyId/text())[1]', 'INT') AS PartyId,
			t.c.value('(Rate/text())[1]', 'MONEY') AS Rate,			
			t.c.value('(FromDate/text())[1]', 'DATE') AS FromDate,		
			t.c.value('(ToDate/text())[1]', 'DATE') AS ToDate,	
			t.c.value('(BasisBilling/text())[1]', 'NVARCHAR(4000)') AS BasisBilling,
			1 AS ChargeType	
	FROM @ChargeSettingXML.nodes('ChargeSettings/ChargeSetting') AS t(c)
	OPTION (OPTIMIZE FOR (@ChargeSettingXML = NULL)) 
	
	DECLARE @CurrentDate DATE = CONVERT(DATE, GETDATE())

	--Get billing group
	;WITH CTE_BillingGroup AS
	(
		SELECT c.PartyId, n.ToParty
		FROM #ChargeSetting c
		CROSS APPLY (
			SELECT TOP(1) ci.ToParty
			FROM dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			WHERE ci.FromParty = c.PartyId 
			ORDER BY ci.ToDate DESC
		) AS n
	)
	UPDATE c
		SET c.GroupId = b.ToParty
	FROM #ChargeSetting c
		INNER JOIN CTE_BillingGroup b ON b.PartyId = c.PartyId

	UPDATE c
		SET c.PartyName = p.PartyName
		    ,c.LicenseeId = p.OldRefID
			,c.GroupName = pt.PartyName
			,c.BaseCurrencyId = pc.BaseCurrencyId
	FROM #ChargeSetting c
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = c.PartyId
		INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN dbo.OAS_PartyBaseCurrency pc WITH(NOLOCK) ON p.PartyID = c.PartyId AND @CurrentDate BETWEEN pc.FromDate AND pc.ToDate
		LEFT JOIN dbo.OAS_Party pt WITH(NOLOCK) ON pt.PartyID = c.GroupId
	WHERE ISNULL(pd.IsDeposit, 0) = 1

	UPDATE c
		SET c.BillerId = n.PartyId
	FROM #ChargeSetting c
	CROSS APPLY (
		SELECT TOP(1) PartyId
		FROM dbo.LA_BillerInfo WITH(NOLOCK)
		WHERE BillerName = CASE c.GroupName WHEN 'Boping' THEN c.GroupName
							                WHEN 'Zelianta' THEN c.GroupName + ' Limited'
						   ELSE '' END
	) AS n

	DECLARE @ID INT = 1
	WHILE 1 = 1
	BEGIN
		SELECT 
			@LicenseeId = LicenseeId
			,@BillerId  = BillerId
			,@PartyId   = PartyId
			,@FromDate  = FromDate
			,@ToDate    = ToDate
			,@Rate      = Rate
			,@PartyName = PartyName
			,@GroupName = GroupName
			,@Groupid   = GroupId
		FROM #ChargeSetting c 
		WHERE ID = @ID

		IF @@ROWCOUNT = 0
			BREAK

		IF EXISTS (SELECT 1 FROM dbo.OAS_ChargeInfo WITH(NOLOCK) WHERE FromParty = @PartyId AND ProductID = @Product3rdId)
		BEGIN
			INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
			VALUES (@PartyId, @PartyName, 101, 'Already launched the selected product')
		END
		ELSE IF NOT EXISTS (
			SELECT 1 
			FROM dbo.OAS_Party p WITH(NOLOCK)
				INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
			WHERE p.PartyType = 1 AND p.PartyID = @PartyId AND pd.StatusId = 1 AND pd.TerminatedDate IS NULL AND pd.SuspendedDate IS NULL
		)
		BEGIN
			INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
			VALUES (@PartyId, @PartyName, 101, 'Not active payer')
		END
		ELSE IF NOT EXISTS (SELECT 1 FROM dbo.LicenseeProduct3rd l WITH(NOLOCK) WHERE l.LicenseeID = @LicenseeId AND l.ProductID = @Product3rdId)
		BEGIN
			INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
			VALUES (@PartyId, @PartyName, 101, 'Not offered selected product yet')
		END
		ELSE 
		BEGIN
			BEGIN TRY	
				UPDATE dbo.LicenseeProduct3rd WITH(ROWLOCK)
				SET EffectiveDate = @LaunchDate, @PreLaunchDate = EffectiveDate
				WHERE LicenseeId = @LicenseeId

				--Insert charge info
				INSERT INTO dbo.OAS_ChargeInfo 
				(
					ProductID
					,FromParty
					,ToParty
					,ParentChargeID
					,Rate
					,BasisOfBilling
					,ChargeType
					,FromDate
					,ToDate
					,BaseCurrencyId
					,FirstOfBilling
				)
				SELECT 
					@Product3rdId
					,PartyId
					,GroupId
					,0
					,Rate
					,BasisBilling
					,ChargeType
					,FromDate
					,ToDate
					,BaseCurrencyId
					,FromDate
				FROM #ChargeSetting
				WHERE ID = @ID

				SET @ChargeID = SCOPE_IDENTITY()

				INSERT INTO dbo.LA_ChargeInfo_SystemMapping (ChargeID, SystemID)
				SELECT @ChargeID, 2
				UNION 
				SELECT @ChargeID, 4
				WHERE @Product3rdId IN (0, 2, 3, 4, 5, 10, 11, 12) AND @Groupid = 1


				;WITH t AS
				(
					SELECT		op.PartyName,
								od.BrandName,
								CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END Product,
								oc.FromDate,
								oc.ToDate,
								oc.FirstOfBilling,
								oc.BasisOfBilling,
								(CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + '%') Rate,
								STRING_AGG(x.Code,',') Currs,
								CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END isMasterRate
					FROM OAS_Party op WITH(NOLOCK)
					INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON op.PartyID = od.PartyID
					INNER JOIN Licensees l WITH(NOLOCK) ON op.OldRefID = l.LicenseeID
					INNER JOIN OAS_ChargeInfo oc WITH(NOLOCK) ON op.PartyID = oc.FromParty AND oc.ProductID IN ( 0,2) and oc.FromDate <=GETDATE() AND GETDATE() <= oc.ToDate 
					CROSS APPLY (
						SELECT DISTINCT lc.Currency, CASE WHEN e.ExchangeId IN (96,202) THEN e.Code + ' (' + e.currency + ')' ELSE e.Code END Code
						FROM LicenseeCust lc  WITH(NOLOCK) 
						INNER JOIN  CustDB.dbo.exchange e with(nolock) on lc.Currency = e.ExchangeId
						WHERE lc.LicenseeID = l.LicenseeID and lc.roleID = 2 and e.ExchangeId <> 20
					) x
					LEFT JOIN  LA_ChargeRateByCurrency lcr WITH(NOLOCK) ON oc.ChargeID = lcr.ChargeID AND x.Currency = lcr.CurrencyID
					LEFT JOIN  Product3rd p3 WITH(NOLOCK) ON oc.ProductID = p3.Productid
					WHERE op.PartyID = @PartyID AND oc.ChargeID = @ChargeID
					GROUP BY op.PartyName,
								od.BrandName,
								CASE WHEN oc.ProductID = 0 THEN 'Sportsbook' ELSE p3.ProductName END,
								oc.FromDate,
								oc.ToDate,
								oc.FirstOfBilling,
								oc.BasisOfBilling,
								CAST (ISNULL(lcr.Rate, oc.Rate) * 100  AS VARCHAR(50) ) + '%',
								CASE WHEN lcr.Rate IS NOT NULL THEN 0 ELSE 1 END
				) 
				, t1 AS
				(
					SELECT t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling,STRING_AGG(cr.r, CHAR(13)) AS r
					FROM t
					CROSS APPLY (
							SELECT CASE WHEN t.isMasterRate = 1 AND EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'Others ' 
										WHEN t.isMasterRate = 1 AND NOT EXISTS (SELECT TOP 1 1 FROM t t2 WHERE t2.isMasterRate = 0 AND t2.Product = t.Product and t2.PartyName = t.PartyName) THEN 'All ' 
										ELSE '' END + '('+ t.Currs + ') - ' + Rate AS r
					) cr
					GROUP BY t.PartyName,t.BrandName,t.Product,t.FromDate,t.ToDate,t.FirstOfBilling,t.BasisOfBilling
				) SELECT @logChargeRate = 
						(
						SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn', crs.crs AS 'crs'
						FROM t1 t 
						CROSS APPLY 
						(
							SELECT 
							(
								SELECT  u.Product p ,  u.FromDate fd, u.ToDate td , u.FirstOfBilling fb, u.BasisOfBilling bb , u.r
								FROM t1 u  WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName FOR JSON PATH
							) crs
						) crs  
						GROUP BY t.PartyName, t.BrandName, crs.crs
						FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
				)
				--  Write Log ChargeRate Setting
				EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
					@UserId			= @UserID
					,@IP			= @LoginIP
					,@SPName		= 'LA_LaunchNewProductIns'
					,@CustId		= @PartyID
					,@Duration		= @duration
					,@TrackingValue2 = @logChargeRate
					,@TrackingValue = @logChargeRateOld
					,@ActionID		 = @logChargeRateActionID

				-- Insert 
				IF ISNULL(@BillerId, 0) <> 0
				BEGIN
					-- Old log biller
					; WITH Items AS 
					(
						SELECT		op.PartyName
									,od.BrandName
									,b.BillerName
									,lt.InvTypeName
									,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
									,temp.InvTemplateName
									, CASE WHEN li.ActiveAddress = 1 THEN od.Address1
											WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
									,STRING_AGG(CASE WHEN li.ProductID = 0 THEN 'Sportsbook' ELSE p.ProductName END,',') ProductIDs
						FROM  LA_InvoiceSetting li with(nolock) 
						INNER JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
						INNER JOIN OAS_Party op WITH(NOLOCK) ON li.FromPartyId = op.PartyID
						INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
						INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
						LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
						LEFT JOIN Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
						WHERE li.FromPartyID =@PartyId AND li.ToPartyId = @BillerID
						GROUP BY op.PartyName, od.BrandName, b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
								, temp.InvTemplateName ,li.ActiveAddress
								,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END
					), ItemsDetail AS
					(
						SELECT t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
						FROM Items t
						CROSS APPLY (
							SELECT 
							(
								SELECT InvTypeName AS it,  InvTemplateName AS itn , ActiveAddress AS ad,  ProductIDs  AS p
								FROM Items u
								WHERE  t.PartyName = u.PartyName AND t.BrandName = u.BrandName AND t.BillerName = u.BillerName AND  t.Bank = u.Bank
								FOR JSON PATH
							) AS iv
						) x
						GROUP BY  t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
					) SELECT @logBillerOld = 
						(   
							SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn' , x.x AS 'bl'
							FROM ItemsDetail t
							CROSS APPLY 
							(
								SELECT
								(
									SELECT u.BillerName AS bln, u.Bank AS b, JSON_QUERY(u.iv) iv
									FROM ItemsDetail u 
									WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName
									FOR JSON PATH
								) x
							) x
							GROUP BY t.PartyName, t.BrandName, x.x 
							FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
						)

					INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
					OUTPUT inserted.InvSettingId INTO @Tmp (InvSettingId)
					SELECT 
						@PartyId
						,@BillerId
						,@Product3rdId 
						,InvTypeId
						,InvTemplateId
						,0 AS BankId
						,1 AS ActiveAddress
					FROM (
						SELECT InvTemplateId, InvTemplateName
							,CASE InvTemplateName
								WHEN @GroupName THEN 1 -- Software Data & Licensing Fees
								WHEN 'Credit' THEN 4 -- Credit Note
								ELSE 5 -- Debit Note
								END AS InvTypeId
						FROM dbo.LA_InvoiceTemplate WITH (NOLOCK)
						WHERE 1 = CASE InvTemplateName
									WHEN @GroupName THEN 1
									WHEN 'Credit' THEN 1
									WHEN 'Debit' + CASE WHEN @GroupName = 'Zelianta' THEN '-Zelianta' ELSE '' END THEN 1
									ELSE 0 END
					) ivt	
				   WHERE ivt.InvTemplateName IN ('Boping', 'Zelianta')
						AND NOT EXISTS (
							SELECT 1 FROM dbo.LA_InvoiceSetting l WITH(NOLOCK) 
							WHERE l.FromPartyId = @PartyId AND ToPartyId = @BillerId AND l.InvTypeId = ivt.InvTypeId AND l.ProductId = @Product3rdId
						)

					-- New log biller
					; WITH Items AS 
					(
						SELECT		op.PartyName
									,od.BrandName
									,b.BillerName
									,lt.InvTypeName
									,CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END Bank
									,temp.InvTemplateName
									, CASE WHEN li.ActiveAddress = 1 THEN od.Address1
											WHEN li.ActiveAddress = 2 THEN od.Address2 END ActiveAddress
									,STRING_AGG(CASE WHEN li.ProductID = 0 THEN 'Sportsbook' ELSE p.ProductName END,',') ProductIDs
						FROM  LA_InvoiceSetting li with(nolock) 
						INNER JOIN LA_InvoiceType lt with(nolock) ON li.InvTypeID  = lt.InvTypeID
						INNER JOIN OAS_Party op WITH(NOLOCK) ON li.FromPartyId = op.PartyID
						INNER JOIN OAS_PartyDetail od WITH(NOLOCK) ON od.PartyID = op.PartyID
						INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON li.ToPartyId = b.PartyId
						LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON li.InvTempId = temp.InvTemplateId
						LEFT JOIN Product3rd p WITH (NOLOCK) ON li.ProductId = p.Productid
						WHERE li.FromPartyID =@PartyId AND li.ToPartyId = @BillerID
						GROUP BY op.PartyName, od.BrandName, b.BillerName, lt.InvTypeName, CASE WHEN li.BankId > 0 THEN 'Bank ' + CAST(li.BankId AS VARCHAR(3)) ELSE '' END
								, temp.InvTemplateName ,li.ActiveAddress
								,CASE WHEN li.ActiveAddress = 1 THEN od.Address1
									WHEN li.ActiveAddress = 2 THEN od.Address2 END
					), ItemsDetail AS
					(
						SELECT t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
						FROM Items t
						CROSS APPLY (
							SELECT 
							(
								SELECT InvTypeName AS it,  InvTemplateName AS itn , ActiveAddress AS ad,  ProductIDs  AS p
								FROM Items u
								WHERE  t.PartyName = u.PartyName AND t.BrandName = u.BrandName AND t.BillerName = u.BillerName AND  t.Bank = u.Bank
								FOR JSON PATH
							) AS iv
						) x
						GROUP BY  t.PartyName,t.BrandName, t.BillerName, t.Bank, x.iv
					) SELECT @logBiller = 
						(   
							SELECT t.PartyName as 'pi.pn', t.BrandName AS 'pi.bn' , x.x AS 'bl'
							FROM ItemsDetail t
							CROSS APPLY 
							(
								SELECT
								(
									SELECT u.BillerName AS bln, u.Bank AS b, JSON_QUERY(u.iv) iv
									FROM ItemsDetail u 
									WHERE u.PartyName = t.PartyName AND u.BrandName = t.BrandName
									FOR JSON PATH
								) x
							) x
							GROUP BY t.PartyName, t.BrandName, x.x 
							FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
						)

					-- Write log 
					EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
						@UserId			= @UserID
						,@IP			= @LoginIP
						,@SPName		= 'LA_LaunchNewProductIns'
						,@CustId		= @PartyId
						,@Duration		= @duration
						,@TrackingValue2 = @logBiller
						,@TrackingValue =  @logBillerOld
						,@ActionID		= @logBillerActionID
				END 
			END TRY
			BEGIN CATCH
				--Rollback
				INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
				VALUES (@PartyId, @PartyName, ERROR_NUMBER(), ERROR_MESSAGE())

				UPDATE dbo.LicenseeProduct3rd WITH(ROWLOCK)
				SET EffectiveDate = @PreLaunchDate
				WHERE LicenseeId = @LicenseeId

				DELETE dbo.OAS_ChargeInfo WITH(ROWLOCK, UPDLOCK) WHERE ChargeID = @ChargeID

				DELETE dbo.LA_ChargeInfo_SystemMapping WITH(ROWLOCK, UPDLOCK) WHERE ChargeID = @ChargeID
				
				DELETE i 
				FROM dbo.LA_InvoiceSetting i WITH(ROWLOCK, UPDLOCK) 
				WHERE i.InvSettingId IN (SELECT t.InvSettingId FROM @Tmp t)

				GOTO GetValue
			END CATCH

			--Update PT on NAP
			SELECT @ProductId = p.ProductId FROM DBPRO.bodb02.dbo.Products p WITH(NOLOCK) WHERE p.ProductPrefix = @ProductCode

			SELECT @SiteName = l.LicenseeName FROM dbo.Licensees l WITH(NOLOCK) WHERE l.LicenseeID = @LicenseeId

			SELECT @InputPT = CONVERT(VARCHAR(MAX), 
			(
				SELECT @ProductId AS '@PID', 0 AS '@CID', 100 * (1 - @Rate) AS '@PT'
				FOR XML PATH('PT'), ROOT('ROOT')
			))
		
			/*Delete prevent updating unexpected NAP PT value*/
			IF ((@Rate > 0.12 AND @SiteName <> '9wickets' OR @Rate = 0) AND @ProductId = 1) OR @SiteName IN ('CandyA18') OR @Product3rdId IN (14, 17, 3, 31, 10, 13, 16) OR @ToDate < GETDATE() 
			BEGIN
				SET @InputPT = ''
			END

			IF @SiteName NOT IN ('', 'CandyA18') AND ISNULL(@InputPT, '') <> ''
			BEGIN
				IF @CurrentDate NOT BETWEEN @FromDate AND @ToDate
				BEGIN
					INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
					VALUES (@PartyId, @PartyName, 10001, 'NAP PT update failed due to it''s not current charge rate.')
				END
				ELSE
				BEGIN
					EXEC CustDB.dbo.Acc_Dep_LicenseeSetting_PTSettingUpd 
						@Site		= @SiteName
						,@InputPT	= @InputPT
						,@UserID	= @UserID
						,@UserName	= @UserName
						,@IP		= @LoginIP
						,@ErrCode	= @ErrCode OUTPUT
						,@ErrMsg	= @ErrMsg OUTPUT

					IF @ErrCode <> 0
					BEGIN
						INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
						VALUES (@PartyId, @PartyName, @ErrCode, @ErrMsg)
					END
				END
			END
		END

		GetValue: 
			SET @ID += 1
	END

	IF EXISTS (SELECT 1 FROM @ErrorMessage)
	BEGIN
		SELECT @ErrMsg = ISNULL(@ErrMsg, '') + PartyName + ': ' + ErrMsg + '<br>'
		FROM @ErrorMessage

		SELECT @ErrMsg = STUFF(@ErrMsg, LEN(@ErrMsg) - 3, 4, ''),  @ErrCode = 101
	END

	-- Write log
	SET @EndRun = GETDATE()
	SET @Duration = DATEDIFF(MILLISECOND, @StartRun, @EndRun)

	SELECT @Doing = CONVERT(NVARCHAR(MAX),
					(
						SELECT 
							PartyId AS '@PartyId'
							,PartyName AS '@PartyName'
							,Rate AS '@Rate'
							,ChargeType AS '@ChargeType'
							,FromDate AS '@FromDate'
							,ToDate AS '@ToDate'
							,BasisBilling AS '@BasisBilling'
							,BaseCurrencyId AS '@BaseCurrencyId'
							,GroupId AS '@GroupId'
							,GroupName AS '@GroupName'
							,BillerId AS '@BillerId'
							,LicenseeId AS '@LicenseeId'
							,@ProductCode AS '@ProductCode'
						FROM #ChargeSetting 
						FOR XML PATH ('r'), ROOT('root')
					))

	EXEC CustDB.dbo.WriteLog_UserLog_UserControl_Wrapper
		@CustID		= 0,
		@Doing		= @Doing,
		@UserID		= @UserID,
		@TypeID		= 0,
		@ActionID	= 5573,
		@Duration	= @Duration

	DROP TABLE #ChargeSetting
END
GO