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
		
	Param's Explannation: 
		+ @ChargeSettingXML: '<ChargeSettings>
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

	DECLARE @ChargeSettingXML XML, @ProductId INT, @Product3rdId TINYINT, @LicenseeId INT, @BillerId INT, @PartyId INT, @GroupName VARCHAR(50), @GroupId INT, @FromDate DATETIME, @ToDate DATETIME
			,@SiteName VARCHAR(20) = '', @InputPT VARCHAR(MAX) = '', @Rate MONEY, @UserName VARCHAR(50) = '', @PartyName VARCHAR(50)

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
			WHERE ci.FromParty = c.PartyId AND @CurrentDate BETWEEN ci.FromDate AND ci.ToDate
		) AS n
	)
	UPDATE c
		SET c.GroupId = b.ToParty
	FROM #ChargeSetting c
		INNER JOIN CTE_BillingGroup b ON b.PartyId = c.PartyId

	UPDATE c
		SET c.PartyName = p.PartyName
		    ,c.LicenseeId = CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE NULL END
			,c.GroupName = pt.PartyName
			,c.BaseCurrencyId = pc.BaseCurrencyId
	FROM #ChargeSetting c
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = c.PartyId
		INNER JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
		LEFT JOIN dbo.OAS_PartyBaseCurrency pc WITH(NOLOCK) ON p.PartyID = c.PartyId AND @CurrentDate BETWEEN pc.FromDate AND pc.ToDate
		LEFT JOIN dbo.OAS_Party pt WITH(NOLOCK) ON pt.PartyID = c.GroupId

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
		FROM #ChargeSetting c 
		WHERE ID = @ID

		IF @@ROWCOUNT = 0
			BREAK

		IF EXISTS (SELECT 1 FROM dbo.OAS_ChargeInfo WITH(NOLOCK) WHERE FromParty = @PartyId AND ProductID = @Product3rdId)
		BEGIN
			INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
			VALUES (@PartyId, @PartyName, 101, 'already launched the selected product')
		END
		ELSE IF NOT EXISTS (SELECT 1 FROM dbo.OAS_Party p WITH(NOLOCK) WHERE p.PartyType = 1 AND p.PartyID = @PartyId)
		BEGIN
			INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
			VALUES (@PartyId, @PartyName, 101, 'not active payer')
		END
		ELSE IF NOT EXISTS (SELECT 1 FROM dbo.LicenseeProduct3rd l WITH(NOLOCK) WHERE l.LicenseeID = @LicenseeId AND l.ProductID = @Product3rdId)
		BEGIN
			INSERT INTO @ErrorMessage (PartyId, PartyName, ErrCode, ErrMsg)
			VALUES (@PartyId, @PartyName, 101, 'not offered selected product yet')
		END
		ELSE 
		BEGIN
			UPDATE dbo.LicenseeProduct3rd WITH(ROWLOCK)
			SET EffectiveDate = @LaunchDate
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
			FROM #ChargeSetting
			WHERE ID = @ID

			-- Insert 
			IF ISNULL(@BillerId, 0) <> 0
			BEGIN
				INSERT INTO dbo.LA_InvoiceSetting (FromPartyId, ToPartyId, ProductId, InvTypeId, InvTempId, BankId, ActiveAddress)
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
			END

			--Update PT on NAP
			SELECT @ProductId = p.ProductId FROM DBPRO.bodb02.dbo.Products p WITH(NOLOCK) WHERE p.ProductPrefix = @ProductCode

			SELECT @SiteName = l.LicenseeName FROM dbo.Licensees l WITH(NOLOCK) WHERE l.LicenseeID = @LicenseeId

			SELECT @InputPT = CONVERT(VARCHAR(MAX), 
			(
				SELECT @ProductId AS '@PID', 0 AS '@CID', 100 * (1 - @Rate) AS '@PT'
				FOR XML PATH('PT'), ROOT('ROOT')
			))
		
			/*Delete prevent updating unexpected NAP PT value*/
			IF ((@Rate > 0.12 AND @SiteName <> '9wickets' OR @Rate = 0) AND @ProductId = 1) OR @SiteName = 'CandyA18'
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

		SET @ID += 1
	END

	IF EXISTS (SELECT 1 FROM @ErrorMessage)
	BEGIN
		SELECT @ErrCode = 101
		SELECT @ErrMsg = ISNULL(@ErrMsg, '') + PartyName + ': ' + ErrMsg + CHAR(13)
		FROM @ErrorMessage
	END

	DROP TABLE #ChargeSetting
END
GO