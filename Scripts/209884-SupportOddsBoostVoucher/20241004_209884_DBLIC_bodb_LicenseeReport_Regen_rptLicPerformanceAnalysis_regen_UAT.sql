/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/
/*
	Created: 20241106@Sally
	DB: DBLIC.bodb_licenseeReport
	Task: Support Odds Boost Voucher [#209884]
	- Regen data table rptLicPerformanceAnalysis_regen_UAT
*/
USE bodb_licenseeReport
GO

	DECLARE @MonthDate TABLE (Id INT IDENTITY(1,1), FromDate Date, ToDate Date)
	INSERT INTO @MonthDate (FromDate, ToDate)
	SELECT '2024-07-01' AS FromDate, '2024-07-31' AS ToDate
	UNION ALL
	SELECT '2024-10-01', '2024-10-31'

	DECLARE	@FromDate   Date 
		,@ToDate		Date 
		,@RowNumber 	INT
		,@MaxRow 	    INT

	SELECT @MaxRow = MAX(Id), @RowNumber = MIN(Id)
	FROM @MonthDate

	WHILE @RowNumber <= @MaxRow
	BEGIN
		SELECT @FromDate = FromDate
			,@ToDate = ToDate
		FROM @MonthDate
		WHERE Id = @RowNumber

		BEGIN
			EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report_xpre 	
				@FromDate		= @FromDate,
				@ToDate			= @ToDate,
				@Environment	= 'PRO'
		
		END	

		PRINT CONCAT(@FromDate,' ', @ToDate)
		SELECT @RowNumber = @RowNumber + 1
		WAITFOR DELAY '000:00:00.005'
	END

