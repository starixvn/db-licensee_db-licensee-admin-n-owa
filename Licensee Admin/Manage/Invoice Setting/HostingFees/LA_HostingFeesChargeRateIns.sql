/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_HostingFeesChargeRateIns]
	@PayerId			INT,
	@BaseCurrencyId		INT,
	@XmlChargeRates		NVARCHAR(MAX),
	@XmlWaives			NVARCHAR(MAX),
	@UserID				INT,
	@LoginIP			VARCHAR (50)	= '',
	@ErrCode			INT				= 0		OUTPUT,
	@ErrMsg				NVARCHAR(1000)	= ''	OUTPUT
AS
/*  
	 Created: 20160620@Bravo
	 Task: Insert hosting fees charge rate settings
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20190510@Percy: Migrate to DBCUST.bodb_Licensee [RedmineID: #103658]

	 Params:
		+ @XmlChargeRates: '<ChargeRates>
								<ChargeRate>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<FirstBilling></FirstBilling>
									<BasisOfBilling></BasisOfBilling>
									<HostingFeesId></HostingFeesId>		
								</ChargeRate>
								<ChargeRate>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<FirstBilling></FirstBilling>
									<BasisOfBilling></BasisOfBilling>
									<HostingFeesId></HostingFeesId>		
								</ChargeRate>
							</ChargeRates>
		+ @@XmlWaives:
							<Waives>
								<Waive>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<BasedMinimunFees></BasedMinimunFees>		
								</Waive>
								<Waive>
									<ChargeId></ChargeId>
									<FromDate></FromDate>
									<ToDate></ToDate>
									<BasedMinimunFees></BasedMinimunFees>		
								</Waive>
							</Waives>'
	 Example:
		EXEC dbo.LA_HostingFeesSel 0
*/
BEGIN
	SET NOCOUNT ON

	-- For writing log
	DECLARE 
		@startRun	DATETIME = GETDATE(),
		@endRun		DATETIME,
		@duration	INT,
		@logData	NVARCHAR(4000),
		@logDataOld	NVARCHAR(4000)

	-- Region: Insert hosting fees details
	DECLARE @ChargeRates AS TABLE (
		ChargeId		INT	,
		FromDate		DATETIME,
		ToDate			DATETIME,
		FirstBilling	DATETIME,
		BasisOfBilling	NVARCHAR(200),
		HostingFeesId	INT,
		RowId			SMALLINT IDENTITY)
	DECLARE @Waives AS TABLE (
		ChargeId		INT	,
		FromDate		DATETIME,
		ToDate			DATETIME,
		BasedMinimunFees INT,
		RowId			SMALLINT IDENTITY)

	DECLARE @idoc1 AS INT
	EXEC sp_xml_preparedocument @idoc1 OUTPUT, @XmlChargeRates

	DECLARE @idoc2 AS INT
	EXEC sp_xml_preparedocument @idoc2 OUTPUT, @XmlWaives

	BEGIN TRY
		INSERT INTO @ChargeRates(ChargeId, FromDate, ToDate, FirstBilling, BasisOfBilling, HostingFeesId)
		SELECT ChargeId, FromDate, ToDate, FirstBilling, BasisOfBilling, HostingFeesId
		FROM OPENXML(@idoc1, 'ChargeRates/ChargeRate')
		WITH (
			ChargeId		INT				'ChargeId',
			FromDate		DATETIME		'FromDate',	
			ToDate			DATETIME		'ToDate',
			FirstBilling	DATETIME		'FirstBilling',
			BasisOfBilling	NVARCHAR(200)	'BasisOfBilling',
			HostingFeesId	INT				'HostingFeesId'
		)

		INSERT INTO @Waives(ChargeId, FromDate, ToDate, BasedMinimunFees)
		SELECT ChargeId, FromDate, ToDate, BasedMinimunFees
		FROM OPENXML(@idoc2, 'Waives/Waive')
		WITH (
			ChargeId		INT				'ChargeId',
			FromDate		DATETIME		'FromDate',	
			ToDate			DATETIME		'ToDate',
			BasedMinimunFees INT			'BasedMinimunFees'
		)

		SET @logDataOld = CAST((SELECT
				c.ChargeId			AS '@ci',
				c.SettingType 		AS '@st',
				c.ParentId 			AS '@pi',
				c.FromParty 		AS '@fp',
				c.ToParty 			AS '@tp',
				c.FromDate 			AS '@fd',
				c.ToDate 			AS '@td',
				c.ProductName 		AS '@pn',
				c.FirstBilling 		AS '@fb',
				c.BasisOfBilling 	AS '@bb',
				c.BaseCurrencyId 	AS '@bc',
				c.HostingFeesId 	AS '@hi',
				c.BasedMinimunFees 	AS '@bf',
				c.Remark 			AS '@rm'
			FROM dbo.LA_HostingFeesSetting c WHERE FromParty = @PayerId
			FOR XML PATH('z'), ROOT('r')
		) AS NVARCHAR(4000))

		SET @logData = CAST((SELECT
				c.ChargeId			AS '@ci',
				c.SettingType 		AS '@st',
				c.ParentId 			AS '@pi',
				c.FromParty 		AS '@fp',
				c.ToParty 			AS '@tp',
				c.FromDate 			AS '@fd',
				c.ToDate 			AS '@td',
				c.ProductName 		AS '@pn',
				c.FirstBilling 		AS '@fb',
				c.BasisOfBilling 	AS '@bb',
				c.BaseCurrencyId 	AS '@bc',
				c.HostingFeesId 	AS '@hi',
				c.BasedMinimunFees 	AS '@bf',
				c.Remark 			AS '@rm'
			FROM ( SELECT ChargeId,
					1 SettingType,
					0 ParentId,
					@PayerId FromParty,
					0 ToParty,
					FromDate,
					ToDate,
					'Hosting' ProductName,
					FirstBilling,
					BasisOfBilling,
					@BaseCurrencyId BaseCurrencyId,
					HostingFeesId,
					NULL BasedMinimunFees,
					'' Remark FROM @ChargeRates
				UNION ALL SELECT ChargeId,
					2 SettingType,
					0 ParentId,
					@PayerId FromParty,
					0 ToParty,
					FromDate,
					ToDate,
					'Hosting' ProductName,
					NULL FirstBilling,
					NULL BasisOfBilling,
					@BaseCurrencyId BaseCurrencyId,
					NULL HostingFeesId,
					BasedMinimunFees,
					'' Remark FROM @Waives
			) c FOR XML PATH('z'), ROOT('r')
		) AS NVARCHAR(4000))
				
		-- validate charge rate settings
		IF EXISTS (
			SELECT 1 FROM @ChargeRates c1 INNER JOIN @ChargeRates c2 ON (
				(c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR
				(c1.ToDate BETWEEN c2.FromDate AND c2.ToDate)
			) WHERE c1.RowId != c2.RowId)
		BEGIN
			SELECT @ErrMsg = 'Cannot save the setting, please check From date/To date.', @ErrCode = 10
			RETURN
		END;

		-- Update charge rate settings
		MERGE dbo.LA_HostingFeesSetting h
		USING @ChargeRates c ON h.ChargeId = c.ChargeId AND h.SettingType=1
		WHEN MATCHED THEN
			UPDATE SET
				h.FromDate = c.FromDate,
				h.ToDate = c.ToDate,
				h.FirstBilling = c.FirstBilling,
				h.BasisOfBilling = c.BasisOfBilling,
				h.HostingFeesId = c.HostingFeesId
		WHEN NOT MATCHED BY TARGET THEN
			INSERT (SettingType,ParentId,FromParty,ToParty,FromDate,ToDate,ProductName,FirstBilling,BasisOfBilling,BaseCurrencyId,HostingFeesId,Remark)
			VALUES (1, 0, @PayerId, 0, c.FromDate, c.ToDate, 'Hosting', c.FirstBilling, c.BasisOfBilling, @BaseCurrencyId, c.HostingFeesId, 'Insert new hosting fees charge rate.')
		WHEN NOT MATCHED BY SOURCE AND h.SettingType=1 AND h.FromParty=@PayerId THEN DELETE;

		-- validate waive settings
		IF EXISTS (
			SELECT 1 FROM @Waives c1 INNER JOIN @Waives c2 ON (
				(c1.FromDate BETWEEN c2.FromDate AND c2.ToDate) OR
				(c1.ToDate BETWEEN c2.FromDate AND c2.ToDate)
			) WHERE c1.RowId != c2.RowId)
		BEGIN
			SELECT @ErrMsg = 'Cannot save waive setting, please check From date/To date.', @ErrCode = 12
			RETURN
		END;

		-- Update waive settings
		MERGE dbo.LA_HostingFeesSetting h
		USING @Waives c ON h.ChargeId = c.ChargeId AND h.SettingType=2
		WHEN MATCHED THEN
			UPDATE SET
				h.FromDate = c.FromDate,
				h.ToDate = c.ToDate,
				h.BasedMinimunFees = c.BasedMinimunFees
		WHEN NOT MATCHED BY TARGET THEN
			INSERT (SettingType,ParentId,FromParty,ToParty,FromDate,ToDate,ProductName,BasedMinimunFees,Remark)
			VALUES (2, 0, @PayerId, 0, c.FromDate, c.ToDate, 'Hosting', c.BasedMinimunFees,'Insert new hosting fees waive.')
		WHEN NOT MATCHED BY SOURCE AND h.SettingType=2 AND h.FromParty=@PayerId THEN DELETE;

	END TRY
	BEGIN CATCH
		SELECT 	@ErrMsg = 'Update failed. Please try again.', @ErrCode = 1
		RETURN
	END CATCH

	EXEC sp_xml_removedocument @idoc1
	EXEC sp_xml_removedocument @idoc2

	-- EndRegion
	
	-- write log
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_HostingFeesChargeRateIns'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logData
		,@OldData		= @logDataOld
	-- EndRegion
END
GO