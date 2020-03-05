/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_PartySpecialTreatmentModify]
	  @PayerID						INT
	, @SpecialTreatmentXml			NVARCHAR (MAX)
	, @UserID						INT
	, @LoginIP						VARCHAR (50)	= ''
	, @ErrCode						INT				= 0		OUTPUT
	, @ErrMsg						NVARCHAR(1000)	= ''	OUTPUT
	, @SpecialTreatmentInsertedList	NVARCHAR(1000)	= ''	OUTPUT
AS
/*
	 Created: 20200305@Parsons
	 Task : Modify Special treatment
	 DB: DBCUST.bodb_Licensee

	 Revisions:
		- 20200305@Parsons: Special handling for INH market [#FeatureID 128570]

	 Params:
		+ @SpecialTreatmentXml: '<SpecialTreatments>
									<SpecialTreatment>
										<Id>1</Id>
										<FromDate>20010203</FromDate>
										<ToDate>20010203</ToDate>
									</SpecialTreatment>	
									<SpecialTreatment>
										<Id>2</Id>
										<FromDate>20020203</FromDate>
										<ToDate>20020203</ToDate>
									</SpecialTreatment>	
								</SpecialTreatments>'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @startRun DATETIME, @endRun	DATETIME, @duration INT, @logSPData NVARCHAR(MAX), @logSPDataOld NVARCHAR(MAX),	@xml XML
	SET @startRun = GETDATE()

	IF ISNULL(@SpecialTreatmentXml, '') = '' RETURN

	DECLARE @SpecialTreatment AS TABLE (Idx INT IDENTITY(1,1), Id INT,FromDate DATE, ToDate DATE, IsEdit BIT)
	DECLARE @idoc AS INT
	EXEC sp_xml_preparedocument @idoc OUTPUT, @SpecialTreatmentXml
	
	BEGIN TRY
		INSERT INTO @SpecialTreatment(Id, FromDate, ToDate, IsEdit)
		SELECT Id
			, FromDate
			, ToDate
			, 1
		FROM OPENXML(@idoc, 'SpecialTreatments/SpecialTreatment')
		WITH (				
			 Id				INT				'Id'
			, FromDate		DATE			'FromDate'
			, ToDate		DATE			'ToDate'
		)
	END TRY
	BEGIN CATCH
		SELECT 	@ErrMsg = 'There''s something wrong with Special treatment, update failed. Please try again.', @ErrCode = 802
		RETURN
	END CATCH

	EXEC sp_xml_removedocument @idoc

	-- fromdate must less than todate
	IF EXISTS (SELECT TOP 1 1 FROM @SpecialTreatment WHERE FromDate > ToDate)
	BEGIN
		SELECT @ErrMsg = 'From Date could not be later than To Date', @ErrCode = 801
		RETURN
	END

	-- check time overlaping
	INSERT INTO @SpecialTreatment(Id, FromDate, ToDate, IsEdit)
	SELECT p2.Id, p2.FromDate, p2.ToDate, 0
	FROM dbo.LA_PartySpecialTreatment p1 WITH (NOLOCK)
	LEFT JOIN @SpecialTreatment p2 ON p1.Id = p2.Id
	WHERE PartyId = @PayerID AND p2.Id IS NULL

	---check case Update , compare new data with old config
	IF EXISTS (
		SELECT TOP 1 1
		FROM @SpecialTreatment a LEFT JOIN @SpecialTreatment b ON a.Idx != b.Idx AND a.Id = b.Id
		WHERE  (a.FromDate BETWEEN b.FromDate AND b.ToDate
					OR a.ToDate BETWEEN b.FromDate AND b.ToDate
					OR b.FromDate BETWEEN a.FromDate AND a.ToDate
					OR b.ToDate BETWEEN a.FromDate AND a.ToDate
				))
	BEGIN		
		--raise error
		SELECT @ErrMsg = 'From date/To date are overlapped with the others, please try again!'
			, @ErrCode = 800
		RETURN
	END

	DELETE @SpecialTreatment WHERE IsEdit = 0

	-- write log
	-- build log string
	SET @xml = (
		SELECT	p1.Id			AS '@Id'
			, p1.PartyId		AS '@p'
			, p1.FromDate		AS '@fd'
			, p1.ToDate			AS '@td'
		FROM dbo.LA_PartySpecialTreatment p1
		WHERE p1.PartyId = @PayerID AND p1.Id IN (
			SELECT p2.Id FROM @SpecialTreatment p2
		)
		FOR XML PATH('z'), ROOT('r')
	)
	SET @logSPDataOld = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"')

	DECLARE @MergeOutput AS TABLE (Id INT, [$action] VARCHAR(20))

	;MERGE dbo.LA_PartySpecialTreatment WITH (ROWLOCK, UPDLOCK) AS t
	USING @SpecialTreatment AS s ON t.Id = s.Id AND t.PartyId = @PayerID
	WHEN MATCHED THEN
		UPDATE SET  t.FromDate = s.FromDate, 
					t.ToDate = s.ToDate
	WHEN NOT MATCHED BY TARGET THEN
		INSERT (PartyId, FromDate, ToDate)
		VALUES (@PayerId, s.FromDate, s.ToDate)
	OUTPUT INSERTED.Id, $action INTO @MergeOutput;

	IF @@ERROR <> 0
	BEGIN
		SELECT @ErrMsg = 'Update failed. Please try again.', @ErrCode = 802	
		RETURN
	END

	SELECT @SpecialTreatmentInsertedList = COALESCE(@SpecialTreatmentInsertedList + ',' + CAST(Id AS VARCHAR), CAST(Id AS VARCHAR))
	FROM @MergeOutput WHERE [$action]='INSERT'

	SET @xml = (
		SELECT	p1.Id			AS '@Id'
			, p1.PartyId		AS '@p'
			, p1.FromDate		AS '@fd'
			, p1.ToDate			AS '@td'
		FROM dbo.LA_PartySpecialTreatment p1
		WHERE p1.PartyId = @PayerID AND p1.Id IN (
			SELECT p2.Id FROM @SpecialTreatment p2
		)
		FOR XML PATH('z'), ROOT('r')
	)
	SET @logSPData = REPLACE(CONVERT(NVARCHAR(MAX), @xml), '" />', '"/"')
	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun) 

	-- Write Log
	EXEC CustDB.dbo.NAP_SpecialCustSetting_WriteLog_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIP
		,@LicenseeID	= 0
		,@CurrencyID	= 0
		,@SPName		= 'LA_PartySpecialTreatmentModify'
		,@CustId		= 0
		,@Duration		= @duration
		,@Data			= @logSPData
		,@OldData		= @logSPDataOld
END
GO